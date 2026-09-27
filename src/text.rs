//! The `.qlin` text format: parser and printer.
//!
//! The printer writes floats in Rust's shortest round-trip form, so
//! `print(parse(print(p))) == print(p)` for every valid program `p`.

use std::collections::BTreeMap;
use std::fmt::{self, Write as _};

use crate::ir::{Bit, BitExpr, Block, Gate, Op, Program, Qubit, ValidateError};

/// Upper bound on the ops that `repeat` may create, to reject input that
/// would unroll without limit.
const MAX_UNROLLED_OPS: usize = 1 << 20;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ParseError {
    pub line: usize,
    pub col: usize,
    pub msg: String,
}

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}:{}: {}", self.line, self.col, self.msg)
    }
}

impl std::error::Error for ParseError {}

#[derive(Clone, Debug, PartialEq)]
enum Tok {
    Ident(String),
    Num(f64),
    LBrace,
    RBrace,
    LParen,
    RParen,
    Comma,
    Arrow,
    Bang,
    Amp,
    Pipe,
    Caret,
    Plus,
    Minus,
    Star,
    Slash,
    Eof,
}

#[derive(Clone, Debug)]
struct Token {
    tok: Tok,
    line: usize,
    col: usize,
}

fn lex(src: &str) -> Result<Vec<Token>, ParseError> {
    let chars: Vec<char> = src.chars().collect();
    let mut out = Vec::new();
    let (mut i, mut line, mut col) = (0, 1, 1);
    while i < chars.len() {
        let c = chars[i];
        let (tline, tcol) = (line, col);
        let err = |msg: String| ParseError {
            line: tline,
            col: tcol,
            msg,
        };
        if c == '\n' {
            i += 1;
            line += 1;
            col = 1;
            continue;
        }
        if c.is_whitespace() {
            i += 1;
            col += 1;
            continue;
        }
        if c == '#' {
            while i < chars.len() && chars[i] != '\n' {
                i += 1;
            }
            continue;
        }
        let start = i;
        let tok = if c.is_ascii_alphabetic() || c == '_' {
            while i < chars.len() && (chars[i].is_ascii_alphanumeric() || chars[i] == '_') {
                i += 1;
            }
            Tok::Ident(chars[start..i].iter().collect())
        } else if c.is_ascii_digit() || c == '.' {
            while i < chars.len() && (chars[i].is_ascii_digit() || chars[i] == '.') {
                i += 1;
            }
            if i < chars.len() && (chars[i] == 'e' || chars[i] == 'E') {
                i += 1;
                if i < chars.len() && (chars[i] == '+' || chars[i] == '-') {
                    i += 1;
                }
                while i < chars.len() && chars[i].is_ascii_digit() {
                    i += 1;
                }
            }
            let text: String = chars[start..i].iter().collect();
            Tok::Num(
                text.parse()
                    .map_err(|_| err(format!("bad number `{text}`")))?,
            )
        } else {
            i += 1;
            match c {
                '{' => Tok::LBrace,
                '}' => Tok::RBrace,
                '(' => Tok::LParen,
                ')' => Tok::RParen,
                ',' => Tok::Comma,
                '!' => Tok::Bang,
                '&' => Tok::Amp,
                '|' => Tok::Pipe,
                '^' => Tok::Caret,
                '+' => Tok::Plus,
                '*' => Tok::Star,
                '/' => Tok::Slash,
                '-' if chars.get(i) == Some(&'>') => {
                    i += 1;
                    Tok::Arrow
                }
                '-' => Tok::Minus,
                _ => return Err(err(format!("unexpected character `{c}`"))),
            }
        };
        col += i - start;
        out.push(Token {
            tok,
            line: tline,
            col: tcol,
        });
    }
    out.push(Token {
        tok: Tok::Eof,
        line,
        col,
    });
    Ok(out)
}

fn indexed(name: &str, prefix: char) -> Option<u32> {
    let rest = name.strip_prefix(prefix)?;
    if rest.is_empty() || !rest.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    rest.parse().ok()
}

struct Parser {
    toks: Vec<Token>,
    pos: usize,
    customs: BTreeMap<String, Gate>,
    unrolled: usize,
}

impl Parser {
    fn peek(&self) -> &Tok {
        &self.toks[self.pos].tok
    }

    fn next(&mut self) -> Token {
        let t = self.toks[self.pos].clone();
        if t.tok != Tok::Eof {
            self.pos += 1;
        }
        t
    }

    fn err_at(&self, t: &Token, msg: impl Into<String>) -> ParseError {
        ParseError {
            line: t.line,
            col: t.col,
            msg: msg.into(),
        }
    }

    fn err_here(&self, msg: impl Into<String>) -> ParseError {
        let t = self.toks[self.pos].clone();
        self.err_at(&t, msg)
    }

    fn expect(&mut self, want: Tok, what: &str) -> Result<(), ParseError> {
        let t = self.next();
        if t.tok == want {
            Ok(())
        } else {
            Err(self.err_at(&t, format!("expected {what}, found {:?}", t.tok)))
        }
    }

    fn keyword(&mut self, kw: &str) -> Result<(), ParseError> {
        let t = self.next();
        match &t.tok {
            Tok::Ident(s) if s == kw => Ok(()),
            other => Err(self.err_at(&t, format!("expected `{kw}`, found {other:?}"))),
        }
    }

    fn uint(&mut self, what: &str) -> Result<u32, ParseError> {
        let t = self.next();
        match t.tok {
            Tok::Num(v) if v >= 0.0 && v.fract() == 0.0 && v <= u32::MAX as f64 => Ok(v as u32),
            ref other => Err(self.err_at(&t, format!("expected {what}, found {other:?}"))),
        }
    }

    fn ident(&mut self, what: &str) -> Result<(Token, String), ParseError> {
        let t = self.next();
        match &t.tok {
            Tok::Ident(s) => {
                let s = s.clone();
                Ok((t, s))
            }
            other => Err(self.err_at(&t, format!("expected {what}, found {other:?}"))),
        }
    }

    fn qubit(&mut self) -> Result<Qubit, ParseError> {
        let (t, s) = self.ident("a qubit `qN`")?;
        indexed(&s, 'q')
            .map(Qubit)
            .ok_or_else(|| self.err_at(&t, format!("expected a qubit `qN`, found `{s}`")))
    }

    fn bit(&mut self) -> Result<Bit, ParseError> {
        let (t, s) = self.ident("a bit `cN`")?;
        indexed(&s, 'c')
            .map(Bit)
            .ok_or_else(|| self.err_at(&t, format!("expected a bit `cN`, found `{s}`")))
    }

    fn program(&mut self) -> Result<Program, ParseError> {
        self.keyword("qubits")?;
        let n_qubits = self.uint("a qubit count")?;
        self.keyword("bits")?;
        let n_bits = self.uint("a bit count")?;
        while matches!(self.peek(), Tok::Ident(s) if s == "opaque") {
            self.next();
            let (t, name) = self.ident("a gate name")?;
            if Gate::builtin(&name).is_some() || self.customs.contains_key(&name) {
                return Err(self.err_at(&t, format!("gate `{name}` is already defined")));
            }
            let arity = self.uint("an arity")? as usize;
            let n_params = self.uint("a parameter count")? as usize;
            if arity == 0 {
                return Err(self.err_at(&t, "an opaque gate needs at least one qubit"));
            }
            self.customs.insert(
                name.clone(),
                Gate::Custom {
                    name,
                    arity,
                    n_params,
                },
            );
        }
        let body = self.block_until(&Tok::Eof)?;
        Ok(Program {
            n_qubits,
            n_bits,
            body,
        })
    }

    /// Parses statements until `end` (not consumed).
    fn block_until(&mut self, end: &Tok) -> Result<Block, ParseError> {
        let mut ops = Vec::new();
        while self.peek() != end {
            if *self.peek() == Tok::Eof {
                return Err(self.err_here("unexpected end of input"));
            }
            self.statement(&mut ops)?;
        }
        Ok(ops)
    }

    fn braced(&mut self) -> Result<Block, ParseError> {
        self.expect(Tok::LBrace, "`{`")?;
        let b = self.block_until(&Tok::RBrace)?;
        self.expect(Tok::RBrace, "`}`")?;
        Ok(b)
    }

    fn statement(&mut self, ops: &mut Block) -> Result<(), ParseError> {
        let (t, word) = self.ident("a statement")?;
        match word.as_str() {
            "measure" => {
                let q = self.qubit()?;
                self.expect(Tok::Arrow, "`->`")?;
                let b = self.bit()?;
                ops.push(Op::Measure { q, b });
            }
            "reset" => {
                let q = self.qubit()?;
                ops.push(Op::Reset { q });
            }
            "if" => {
                let cond = self.bexpr()?;
                let then_ = self.braced()?;
                let else_ = if matches!(self.peek(), Tok::Ident(s) if s == "else") {
                    self.next();
                    self.braced()?
                } else {
                    Vec::new()
                };
                ops.push(Op::If { cond, then_, else_ });
            }
            "repeat" => {
                let n = self.uint("a repeat count")? as usize;
                let body = self.braced()?;
                let added = n.saturating_mul(body.len().max(1));
                self.unrolled = self.unrolled.saturating_add(added);
                if self.unrolled > MAX_UNROLLED_OPS {
                    return Err(self.err_at(&t, "repeat unrolls to too many ops"));
                }
                for _ in 0..n {
                    ops.extend(body.iter().cloned());
                }
            }
            "switch" => {
                let mut bits = vec![self.bit()?];
                while matches!(self.peek(), Tok::Ident(s) if indexed(s, 'c').is_some()) {
                    bits.push(self.bit()?);
                }
                self.expect(Tok::LBrace, "`{`")?;
                let (mut cases, mut default) = (Vec::new(), Vec::new());
                while *self.peek() != Tok::RBrace {
                    let (t, word) = self.ident("`case` or `default`")?;
                    match word.as_str() {
                        "case" => {
                            let mut v = Vec::with_capacity(bits.len());
                            for _ in 0..bits.len() {
                                v.push(match self.uint("a case bit 0 or 1")? {
                                    0 => false,
                                    1 => true,
                                    _ => return Err(self.err_at(&t, "case bits are 0 or 1")),
                                });
                            }
                            cases.push((v, self.braced()?));
                        }
                        "default" => default = self.braced()?,
                        other => {
                            return Err(self.err_at(
                                &t,
                                format!("expected `case` or `default`, found `{other}`"),
                            ))
                        }
                    }
                }
                self.expect(Tok::RBrace, "`}`")?;
                ops.push(Op::Switch {
                    bits,
                    cases,
                    default,
                });
            }
            "loop" => {
                self.keyword("max")?;
                let max_iters = self.uint("an iteration bound")?;
                let body = self.braced()?;
                self.keyword("until")?;
                let until = self.bexpr()?;
                ops.push(Op::Loop {
                    body,
                    until,
                    max_iters,
                });
            }
            name => {
                let gate = Gate::builtin(name)
                    .or_else(|| self.customs.get(name).cloned())
                    .ok_or_else(|| self.err_at(&t, format!("unknown gate `{name}`")))?;
                let mut params = Vec::new();
                if *self.peek() == Tok::LParen {
                    self.next();
                    params.push(self.pexpr()?);
                    while *self.peek() == Tok::Comma {
                        self.next();
                        params.push(self.pexpr()?);
                    }
                    self.expect(Tok::RParen, "`)`")?;
                }
                let mut qubits = Vec::with_capacity(gate.arity());
                for _ in 0..gate.arity() {
                    qubits.push(self.qubit()?);
                }
                ops.push(Op::Gate {
                    gate,
                    qubits,
                    params,
                });
            }
        }
        Ok(())
    }

    // Parameter expressions: + - * / unary minus, `pi`, numbers.
    fn pexpr(&mut self) -> Result<f64, ParseError> {
        let mut v = self.pterm()?;
        while matches!(self.peek(), Tok::Plus | Tok::Minus) {
            let op = self.next().tok;
            let rhs = self.pterm()?;
            if op == Tok::Plus {
                v += rhs;
            } else {
                v -= rhs;
            }
        }
        Ok(v)
    }

    fn pterm(&mut self) -> Result<f64, ParseError> {
        let mut v = self.punary()?;
        while matches!(self.peek(), Tok::Star | Tok::Slash) {
            let op = self.next().tok;
            let rhs = self.punary()?;
            if op == Tok::Star {
                v *= rhs;
            } else {
                v /= rhs;
            }
        }
        Ok(v)
    }

    fn punary(&mut self) -> Result<f64, ParseError> {
        let t = self.next();
        match &t.tok {
            Tok::Minus => Ok(-self.punary()?),
            Tok::Num(v) => Ok(*v),
            Tok::Ident(s) if s == "pi" => Ok(std::f64::consts::PI),
            Tok::LParen => {
                let v = self.pexpr()?;
                self.expect(Tok::RParen, "`)`")?;
                Ok(v)
            }
            other => Err(self.err_at(&t, format!("expected a parameter, found {other:?}"))),
        }
    }

    // Bit expressions, loosest first: | then ^ then & then !.
    fn bexpr(&mut self) -> Result<BitExpr, ParseError> {
        let mut e = self.bxor()?;
        while *self.peek() == Tok::Pipe {
            self.next();
            e = e.or(self.bxor()?);
        }
        Ok(e)
    }

    fn bxor(&mut self) -> Result<BitExpr, ParseError> {
        let mut e = self.band()?;
        while *self.peek() == Tok::Caret {
            self.next();
            e = e.xor(self.band()?);
        }
        Ok(e)
    }

    fn band(&mut self) -> Result<BitExpr, ParseError> {
        let mut e = self.bnot()?;
        while *self.peek() == Tok::Amp {
            self.next();
            e = e.and(self.bnot()?);
        }
        Ok(e)
    }

    fn bnot(&mut self) -> Result<BitExpr, ParseError> {
        let t = self.next();
        match &t.tok {
            Tok::Bang => Ok(self.bnot()?.not()),
            Tok::LParen => {
                let e = self.bexpr()?;
                self.expect(Tok::RParen, "`)`")?;
                Ok(e)
            }
            Tok::Num(v) if *v == 0.0 => Ok(BitExpr::Const(false)),
            Tok::Num(v) if *v == 1.0 => Ok(BitExpr::Const(true)),
            Tok::Ident(s) => indexed(s, 'c')
                .map(BitExpr::bit)
                .ok_or_else(|| self.err_at(&t, format!("expected a bit `cN`, found `{s}`"))),
            other => Err(self.err_at(&t, format!("expected a bit expression, found {other:?}"))),
        }
    }
}

#[derive(Debug)]
pub enum LoadError {
    Parse(ParseError),
    Invalid(ValidateError),
}

impl fmt::Display for LoadError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            LoadError::Parse(e) => write!(f, "parse error at {e}"),
            LoadError::Invalid(e) => write!(f, "invalid program: {e}"),
        }
    }
}

impl std::error::Error for LoadError {}

/// Parses and validates a `.qlin` program.
pub fn parse(src: &str) -> Result<Program, LoadError> {
    let toks = lex(src).map_err(LoadError::Parse)?;
    let mut p = Parser {
        toks,
        pos: 0,
        customs: BTreeMap::new(),
        unrolled: 0,
    };
    let prog = p.program().map_err(LoadError::Parse)?;
    prog.validate().map_err(LoadError::Invalid)?;
    Ok(prog)
}

fn prec(e: &BitExpr) -> u8 {
    match e {
        BitExpr::Or(..) => 1,
        BitExpr::Xor(..) => 2,
        BitExpr::And(..) => 3,
        BitExpr::Not(_) => 4,
        BitExpr::Const(_) | BitExpr::Bit(_) => 5,
    }
}

fn write_bexpr(out: &mut String, e: &BitExpr, min_prec: u8) {
    let paren = prec(e) < min_prec;
    if paren {
        out.push('(');
    }
    match e {
        BitExpr::Const(c) => out.push(if *c { '1' } else { '0' }),
        BitExpr::Bit(b) => {
            let _ = write!(out, "c{}", b.0);
        }
        BitExpr::Not(inner) => {
            out.push('!');
            write_bexpr(out, inner, 4);
        }
        BitExpr::And(a, b) | BitExpr::Or(a, b) | BitExpr::Xor(a, b) => {
            let p = prec(e);
            let sym = match e {
                BitExpr::And(..) => " & ",
                BitExpr::Or(..) => " | ",
                _ => " ^ ",
            };
            write_bexpr(out, a, p);
            out.push_str(sym);
            write_bexpr(out, b, p + 1);
        }
    }
    if paren {
        out.push(')');
    }
}

/// Formats a bit expression in `.qlin` syntax.
pub fn format_bexpr(e: &BitExpr) -> String {
    let mut s = String::new();
    write_bexpr(&mut s, e, 0);
    s
}

fn collect_customs(block: &Block, out: &mut BTreeMap<String, Gate>) {
    for op in block {
        match op {
            Op::Gate {
                gate: g @ Gate::Custom { name, .. },
                ..
            } => {
                out.insert(name.clone(), g.clone());
            }
            other => {
                for arm in other.arms() {
                    collect_customs(arm, out);
                }
            }
        }
    }
}

fn write_block(out: &mut String, block: &Block, depth: usize) {
    for op in block {
        write_op(out, op, depth);
    }
}

/// Formats one leaf op (gate, measure, reset) without indentation or
/// newline. Returns `None` for control flow.
pub fn format_leaf(op: &Op) -> Option<String> {
    match op {
        Op::Gate {
            gate,
            qubits,
            params,
        } => {
            let mut s = gate.name().to_string();
            if !params.is_empty() {
                let ps: Vec<String> = params.iter().map(|p| format!("{p:?}")).collect();
                let _ = write!(s, "({})", ps.join(", "));
            }
            for q in qubits {
                let _ = write!(s, " q{}", q.0);
            }
            Some(s)
        }
        Op::Measure { q, b } => Some(format!("measure q{} -> c{}", q.0, b.0)),
        Op::Reset { q } => Some(format!("reset q{}", q.0)),
        Op::If { .. } | Op::Loop { .. } | Op::Switch { .. } => None,
    }
}

fn write_op(out: &mut String, op: &Op, depth: usize) {
    let pad = "  ".repeat(depth);
    if let Some(s) = format_leaf(op) {
        let _ = writeln!(out, "{pad}{s}");
        return;
    }
    match op {
        Op::If { cond, then_, else_ } => {
            let _ = writeln!(out, "{pad}if {} {{", format_bexpr(cond));
            write_block(out, then_, depth + 1);
            if else_.is_empty() {
                let _ = writeln!(out, "{pad}}}");
            } else {
                let _ = writeln!(out, "{pad}}} else {{");
                write_block(out, else_, depth + 1);
                let _ = writeln!(out, "{pad}}}");
            }
        }
        Op::Loop {
            body,
            until,
            max_iters,
        } => {
            let _ = writeln!(out, "{pad}loop max {max_iters} {{");
            write_block(out, body, depth + 1);
            let _ = writeln!(out, "{pad}}} until {}", format_bexpr(until));
        }
        Op::Switch {
            bits,
            cases,
            default,
        } => {
            let names: Vec<String> = bits.iter().map(|b| format!("c{}", b.0)).collect();
            let _ = writeln!(out, "{pad}switch {} {{", names.join(" "));
            for (v, block) in cases {
                let vs: Vec<&str> = v.iter().map(|&x| if x { "1" } else { "0" }).collect();
                let _ = writeln!(out, "{pad}  case {} {{", vs.join(" "));
                write_block(out, block, depth + 2);
                let _ = writeln!(out, "{pad}  }}");
            }
            if !default.is_empty() {
                let _ = writeln!(out, "{pad}  default {{");
                write_block(out, default, depth + 2);
                let _ = writeln!(out, "{pad}  }}");
            }
            let _ = writeln!(out, "{pad}}}");
        }
        _ => unreachable!("leaf ops are handled by format_leaf"),
    }
}

/// Prints a program in canonical `.qlin` form.
pub fn print(prog: &Program) -> String {
    let mut out = String::new();
    let _ = writeln!(out, "qubits {}", prog.n_qubits);
    let _ = writeln!(out, "bits {}", prog.n_bits);
    let mut customs = BTreeMap::new();
    collect_customs(&prog.body, &mut customs);
    for g in customs.values() {
        let _ = writeln!(out, "opaque {} {} {}", g.name(), g.arity(), g.n_params());
    }
    write_block(&mut out, &prog.body, 0);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE: &str = "\
qubits 3
bits 2
opaque foo 2 1
h q0
cx q1 q2   # comment
rz(pi/4) q0
u(0.1, -0.2, 1e-3) q1
foo(2*pi) q0 q2
measure q0 -> c0
if c1 { x q2 }
if c0 & !c1 { z q2 } else { h q2 }
if (c0 | c1) ^ 1 { x q0 }
repeat 3 { h q0 }
loop max 8 { h q0  measure q0 -> c0 } until c0
reset q1
";

    #[test]
    fn parses_sample() {
        let p = parse(SAMPLE).unwrap();
        assert_eq!(p.n_qubits, 3);
        assert_eq!(p.n_bits, 2);
        // 9 statements before `repeat`, 3 unrolled ops, then loop and reset.
        assert_eq!(p.body.len(), 9 + 3 + 2);
        assert_eq!(
            p.body[2],
            Op::Gate {
                gate: Gate::Rz,
                qubits: vec![Qubit(0)],
                params: vec![std::f64::consts::FRAC_PI_4],
            }
        );
    }

    #[test]
    fn print_is_fixed_point() {
        let once = print(&parse(SAMPLE).unwrap());
        let twice = print(&parse(&once).unwrap());
        assert_eq!(once, twice);
        assert_eq!(parse(&once).unwrap(), parse(SAMPLE).unwrap());
    }

    #[test]
    fn precedence_and_parens() {
        let p = parse("qubits 1\nbits 3\nif c0 | c1 & !c2 { x q0 }\nif (c0 | c1) & c2 { x q0 }\n")
            .unwrap();
        let Op::If { cond: a, .. } = &p.body[0] else {
            panic!()
        };
        let Op::If { cond: b, .. } = &p.body[1] else {
            panic!()
        };
        assert_eq!(
            *a,
            BitExpr::bit(0).or(BitExpr::bit(1).and(BitExpr::bit(2).not()))
        );
        assert_eq!(format_bexpr(a), "c0 | c1 & !c2");
        assert_eq!(format_bexpr(b), "(c0 | c1) & c2");
    }

    #[test]
    fn errors_carry_position() {
        let e = parse("qubits 1\nbits 0\n  frob q0\n").unwrap_err();
        let LoadError::Parse(e) = e else { panic!() };
        assert_eq!((e.line, e.col), (3, 3));
        assert!(e.msg.contains("unknown gate"));
    }

    #[test]
    fn validation_runs() {
        let e = parse("qubits 1\nbits 0\ncx q0 q1\n").unwrap_err();
        assert!(matches!(
            e,
            LoadError::Invalid(ValidateError::QubitOutOfRange(_))
        ));
        let e = parse("qubits 2\nbits 0\ncx q1 q1\n").unwrap_err();
        assert!(matches!(
            e,
            LoadError::Invalid(ValidateError::RepeatedQubit { .. })
        ));
        let e = parse("qubits 1\nbits 0\nrz(1/0) q0\n").unwrap_err();
        assert!(matches!(
            e,
            LoadError::Invalid(ValidateError::NonFiniteParam { .. })
        ));
    }

    #[test]
    fn rejects_huge_repeat() {
        let e = parse("qubits 1\nbits 0\nrepeat 4294967295 { h q0 }\n").unwrap_err();
        assert!(matches!(e, LoadError::Parse(_)));
    }
}

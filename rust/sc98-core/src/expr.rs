//! The number boxes' arithmetic, including VB error numbers 11 and 13.
use crate::Dimension;
use alloc::vec::Vec;
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ExprError {
    DivisionByZero,
    TypeMismatch,
    TooDeep,
}
impl ExprError {
    pub fn code(self) -> u8 {
        if self == Self::DivisionByZero {
            11
        } else {
            13
        }
    }
}
struct Parser {
    bytes: Vec<u8>,
    at: usize,
    depth: u8,
}
impl Parser {
    fn peek(&self) -> u8 {
        self.bytes.get(self.at).copied().unwrap_or_default()
    }
    fn factor(&mut self) -> Result<Dimension, ExprError> {
        if self.depth >= 64 {
            return Err(ExprError::TooDeep);
        }
        self.depth += 1;
        let result = match self.peek() {
            b'-' => {
                self.at += 1;
                self.factor().map(|n| -n)
            }
            b'(' => {
                self.at += 1;
                let n = self.sum()?;
                if self.peek() != b')' {
                    return Err(ExprError::TypeMismatch);
                }
                self.at += 1;
                Ok(n)
            }
            _ => {
                let start = self.at;
                while self.peek().is_ascii_digit() || self.peek() == b'.' {
                    self.at += 1;
                }
                if start == self.at {
                    return Err(ExprError::TypeMismatch);
                }
                // VB Val accepts the numeric prefix of a run such as "1.2.3".
                let run = &self.bytes[start..self.at];
                let mut dot = false;
                let end = run
                    .iter()
                    .position(|&b| {
                        if b == b'.' {
                            let old = dot;
                            dot = true;
                            old
                        } else {
                            false
                        }
                    })
                    .unwrap_or(run.len());
                let s = core::str::from_utf8(&run[..end]).map_err(|_| ExprError::TypeMismatch)?;
                if s == "." {
                    Ok(0.0)
                } else {
                    s.parse().map_err(|_| ExprError::TypeMismatch)
                }
            }
        };
        self.depth -= 1;
        result
    }
    fn product(&mut self) -> Result<Dimension, ExprError> {
        let mut n = self.factor()?;
        loop {
            let op = self.peek();
            if op != b'*' && op != b'/' {
                break;
            }
            self.at += 1;
            let v = self.factor()?;
            if op == b'*' {
                n *= v;
            } else {
                if v == 0.0 {
                    return Err(ExprError::DivisionByZero);
                }
                n /= v;
            }
        }
        Ok(n)
    }
    fn sum(&mut self) -> Result<Dimension, ExprError> {
        let mut n = self.product()?;
        loop {
            let op = self.peek();
            if op != b'+' && op != b'-' {
                break;
            }
            self.at += 1;
            let v = self.product()?;
            if op == b'+' {
                n += v;
            } else {
                n -= v;
            }
        }
        Ok(n)
    }
}
pub fn evaluate(input: &str) -> Result<Dimension, ExprError> {
    let mut p = Parser {
        bytes: input.trim().bytes().filter(|&c| c != b' ').collect(),
        at: 0,
        depth: 0,
    };
    let n = p.sum()?;
    if p.at != p.bytes.len() || !n.is_finite() {
        return Err(ExprError::TypeMismatch);
    }
    Ok(n)
}

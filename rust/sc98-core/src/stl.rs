//! Binary STL in the FreeBASIC edition's triangle order, translated positive.
use crate::{mesh::normal, Error, Mesh};
use alloc::{format, vec, vec::Vec};
impl Mesh {
    pub fn to_stl(&self, title: &str) -> Result<Vec<u8>, Error> {
        let first = self.triangles.first().ok_or(Error::EmptyMesh)?;
        let count = u32::try_from(self.triangles.len()).map_err(|_| Error::MeshTooLarge)?;
        let mut min = first.precise[0];
        for t in &self.triangles {
            for p in t.precise {
                for k in 0..3 {
                    if p[k] < min[k] {
                        min[k] = p[k];
                    }
                }
            }
        }
        let title = format!("Binary STL from SolidCraft 98: {title}, mm");
        let mut out = vec![b' '; 80];
        for (dst, c) in out.iter_mut().zip(title.chars()) {
            *dst = u8::try_from(c as u32).unwrap_or(b'?');
        }
        out.extend(count.to_le_bytes());
        for t in &self.triangles {
            for n in normal(t.precise) {
                out.extend((n as f32).to_le_bytes());
            }
            for p in t.precise {
                for k in 0..3 {
                    out.extend(((p[k] - min[k]) as f32).to_le_bytes());
                }
            }
            out.extend([0; 2]);
        }
        Ok(out)
    }
}

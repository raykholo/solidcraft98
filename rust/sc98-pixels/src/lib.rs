//! Hand-drawn SolidCraft 98 graphics. No heap, OS, or core model dependency.
#![no_std]
#![forbid(unsafe_code)]

pub mod app;
pub mod draw;
pub mod font;
pub mod framebuffer;
pub mod icons;
pub mod model;
pub mod view;
pub mod widgets;

/// All geometric arithmetic goes through this alias.
pub type Scalar = f32;

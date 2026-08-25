// Portions adapted from jixunmoe-go/qrc at commit
// 866e996416b0cec7bef648400633f6483c4200d5.
//
// MIT License
//
// Copyright (c) 2023 Jixun Wu
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

use std::fmt;
use std::io::Read;

use flate2::read::ZlibDecoder;

const MAX_QRC_CIPHERTEXT_BYTES: usize = 1024 * 1024;
const MAX_QRC_PLAINTEXT_BYTES: usize = 2 * 1024 * 1024;

const KEY_1: [u8; 8] = *b"!@#)(NHL";
const KEY_2: [u8; 8] = *b"123ZXC!@";
const KEY_3: [u8; 8] = *b"!@#)(*$%";

const KEY_ROUND_SHIFTS: [u8; 16] = [1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1];
const LARGE_STATE_SHIFTS: [u8; 8] = [0x1a, 0x14, 0x0e, 0x08, 0x3a, 0x34, 0x2e, 0x28];
const SBOXES: [[u8; 64]; 8] = [
    [
        14, 0, 4, 15, 13, 7, 1, 4, 2, 14, 15, 2, 11, 13, 8, 1, 3, 10, 10, 6, 6, 12, 12, 11, 5, 9,
        9, 5, 0, 3, 7, 8, 4, 15, 1, 12, 14, 8, 8, 2, 13, 4, 6, 9, 2, 1, 11, 7, 15, 5, 12, 11, 9, 3,
        7, 14, 3, 10, 10, 0, 5, 6, 0, 13,
    ],
    [
        15, 3, 1, 13, 8, 4, 14, 7, 6, 15, 11, 2, 3, 8, 4, 15, 9, 12, 7, 0, 2, 1, 13, 10, 12, 6, 0,
        9, 5, 11, 10, 5, 0, 13, 14, 8, 7, 10, 11, 1, 10, 3, 4, 15, 13, 4, 1, 2, 5, 11, 8, 6, 12, 7,
        6, 12, 9, 0, 3, 5, 2, 14, 15, 9,
    ],
    [
        10, 13, 0, 7, 9, 0, 14, 9, 6, 3, 3, 4, 15, 6, 5, 10, 1, 2, 13, 8, 12, 5, 7, 14, 11, 12, 4,
        11, 2, 15, 8, 1, 13, 1, 6, 10, 4, 13, 9, 0, 8, 6, 15, 9, 3, 8, 0, 7, 11, 4, 1, 15, 2, 14,
        12, 3, 5, 11, 10, 5, 14, 2, 7, 12,
    ],
    [
        7, 13, 13, 8, 14, 11, 3, 5, 0, 6, 6, 15, 9, 0, 10, 3, 1, 4, 2, 7, 8, 2, 5, 12, 11, 1, 12,
        10, 4, 14, 15, 9, 10, 3, 6, 15, 9, 0, 0, 6, 12, 10, 11, 10, 7, 13, 13, 8, 15, 9, 1, 4, 3,
        5, 14, 11, 5, 12, 2, 7, 8, 2, 4, 14,
    ],
    [
        2, 14, 12, 11, 4, 2, 1, 12, 7, 4, 10, 7, 11, 13, 6, 1, 8, 5, 5, 0, 3, 15, 15, 10, 13, 3, 0,
        9, 14, 8, 9, 6, 4, 11, 2, 8, 1, 12, 11, 7, 10, 1, 13, 14, 7, 2, 8, 13, 15, 6, 9, 15, 12, 0,
        5, 9, 6, 10, 3, 4, 0, 5, 14, 3,
    ],
    [
        12, 10, 1, 15, 10, 4, 15, 2, 9, 7, 2, 12, 6, 9, 8, 5, 0, 6, 13, 1, 3, 13, 4, 14, 14, 0, 7,
        11, 5, 3, 11, 8, 9, 4, 14, 3, 15, 2, 5, 12, 2, 9, 8, 5, 12, 15, 3, 10, 7, 11, 0, 14, 4, 1,
        10, 7, 1, 6, 13, 0, 11, 8, 6, 13,
    ],
    [
        4, 13, 11, 0, 2, 11, 14, 7, 15, 4, 0, 9, 8, 1, 13, 10, 3, 14, 12, 3, 9, 5, 7, 12, 5, 2, 10,
        15, 6, 8, 1, 6, 1, 6, 4, 11, 11, 13, 13, 8, 12, 1, 3, 4, 7, 10, 14, 7, 10, 9, 15, 5, 6, 0,
        8, 15, 0, 14, 5, 2, 9, 3, 2, 12,
    ],
    [
        13, 1, 2, 15, 8, 13, 4, 8, 6, 10, 15, 3, 11, 7, 1, 4, 10, 12, 9, 5, 3, 6, 14, 11, 5, 0, 0,
        14, 12, 9, 7, 2, 7, 2, 11, 1, 4, 14, 1, 7, 9, 4, 12, 10, 14, 8, 2, 13, 0, 15, 6, 12, 10, 9,
        13, 0, 15, 3, 3, 5, 5, 6, 8, 11,
    ],
];
const P_BOX: [u8; 32] = [
    0x0f, 0x06, 0x13, 0x14, 0x1c, 0x0b, 0x1b, 0x10, 0x00, 0x0e, 0x16, 0x19, 0x04, 0x11, 0x1e, 0x09,
    0x01, 0x07, 0x17, 0x0d, 0x1f, 0x1a, 0x02, 0x08, 0x12, 0x0c, 0x1d, 0x05, 0x15, 0x0a, 0x03, 0x18,
];
const INITIAL_PERMUTATION: [u8; 64] = [
    0x39, 0x31, 0x29, 0x21, 0x19, 0x11, 0x09, 0x01, 0x3b, 0x33, 0x2b, 0x23, 0x1b, 0x13, 0x0b, 0x03,
    0x3d, 0x35, 0x2d, 0x25, 0x1d, 0x15, 0x0d, 0x05, 0x3f, 0x37, 0x2f, 0x27, 0x1f, 0x17, 0x0f, 0x07,
    0x38, 0x30, 0x28, 0x20, 0x18, 0x10, 0x08, 0x00, 0x3a, 0x32, 0x2a, 0x22, 0x1a, 0x12, 0x0a, 0x02,
    0x3c, 0x34, 0x2c, 0x24, 0x1c, 0x14, 0x0c, 0x04, 0x3e, 0x36, 0x2e, 0x26, 0x1e, 0x16, 0x0e, 0x06,
];
const INVERSE_INITIAL_PERMUTATION: [u8; 64] = [
    0x27, 0x07, 0x2f, 0x0f, 0x37, 0x17, 0x3f, 0x1f, 0x26, 0x06, 0x2e, 0x0e, 0x36, 0x16, 0x3e, 0x1e,
    0x25, 0x05, 0x2d, 0x0d, 0x35, 0x15, 0x3d, 0x1d, 0x24, 0x04, 0x2c, 0x0c, 0x34, 0x14, 0x3c, 0x1c,
    0x23, 0x03, 0x2b, 0x0b, 0x33, 0x13, 0x3b, 0x1b, 0x22, 0x02, 0x2a, 0x0a, 0x32, 0x12, 0x3a, 0x1a,
    0x21, 0x01, 0x29, 0x09, 0x31, 0x11, 0x39, 0x19, 0x20, 0x00, 0x28, 0x08, 0x30, 0x10, 0x38, 0x18,
];
const KEY_PERMUTATION: [u8; 56] = [
    0x38, 0x30, 0x28, 0x20, 0x18, 0x10, 0x08, 0x00, 0x39, 0x31, 0x29, 0x21, 0x19, 0x11, 0x09, 0x01,
    0x3a, 0x32, 0x2a, 0x22, 0x1a, 0x12, 0x0a, 0x02, 0x3b, 0x33, 0x2b, 0x23, 0x3e, 0x36, 0x2e, 0x26,
    0x1e, 0x16, 0x0e, 0x06, 0x3d, 0x35, 0x2d, 0x25, 0x1d, 0x15, 0x0d, 0x05, 0x3c, 0x34, 0x2c, 0x24,
    0x1c, 0x14, 0x0c, 0x04, 0x1b, 0x13, 0x0b, 0x03,
];
const KEY_COMPRESSION: [u8; 48] = [
    0x0d, 0x10, 0x0a, 0x17, 0x00, 0x04, 0x02, 0x1b, 0x0e, 0x05, 0x14, 0x09, 0x16, 0x12, 0x0b, 0x03,
    0x19, 0x07, 0x0f, 0x06, 0x1a, 0x13, 0x0c, 0x01, 0x2d, 0x38, 0x23, 0x29, 0x33, 0x3b, 0x22, 0x2c,
    0x37, 0x31, 0x25, 0x34, 0x30, 0x35, 0x2b, 0x3c, 0x26, 0x39, 0x32, 0x2e, 0x36, 0x28, 0x21, 0x24,
];
const KEY_EXPANSION: [u8; 48] = [
    0x1f, 0x00, 0x01, 0x02, 0x03, 0x04, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x07, 0x08, 0x09, 0x0a,
    0x0b, 0x0c, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10, 0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x13, 0x14,
    0x15, 0x16, 0x17, 0x18, 0x17, 0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x00,
];

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum QrcDecryptError {
    Empty,
    CiphertextTooLarge,
    OddHexLength,
    InvalidHex,
    MisalignedBlocks,
    Decompress,
    PlaintextTooLarge,
    InvalidUtf8,
}

impl fmt::Display for QrcDecryptError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(match self {
            Self::Empty => "QRC ciphertext is empty",
            Self::CiphertextTooLarge => "QRC ciphertext exceeds the safety limit",
            Self::OddHexLength => "QRC ciphertext has an odd hexadecimal length",
            Self::InvalidHex => "QRC ciphertext is not hexadecimal",
            Self::MisalignedBlocks => "QRC ciphertext is not aligned to DES blocks",
            Self::Decompress => "QRC plaintext is not a valid zlib stream",
            Self::PlaintextTooLarge => "QRC plaintext exceeds the safety limit",
            Self::InvalidUtf8 => "QRC plaintext is not UTF-8",
        })
    }
}

impl std::error::Error for QrcDecryptError {}

pub(crate) fn decrypt_cloud_qrc(ciphertext: &str) -> Result<String, QrcDecryptError> {
    let mut encrypted = decode_hex(ciphertext)?;
    for (key, encrypt) in [(KEY_1, false), (KEY_2, true), (KEY_3, false)] {
        Des::new(key, encrypt).transform_bytes(&mut encrypted);
    }

    let mut plaintext = Vec::new();
    ZlibDecoder::new(encrypted.as_slice())
        .take((MAX_QRC_PLAINTEXT_BYTES + 1) as u64)
        .read_to_end(&mut plaintext)
        .map_err(|_| QrcDecryptError::Decompress)?;
    if plaintext.len() > MAX_QRC_PLAINTEXT_BYTES {
        return Err(QrcDecryptError::PlaintextTooLarge);
    }
    String::from_utf8(plaintext).map_err(|_| QrcDecryptError::InvalidUtf8)
}

fn decode_hex(value: &str) -> Result<Vec<u8>, QrcDecryptError> {
    if value.is_empty() {
        return Err(QrcDecryptError::Empty);
    }
    if value.len() > MAX_QRC_CIPHERTEXT_BYTES * 2 {
        return Err(QrcDecryptError::CiphertextTooLarge);
    }
    if !value.len().is_multiple_of(2) {
        return Err(QrcDecryptError::OddHexLength);
    }

    let mut bytes = Vec::with_capacity(value.len() / 2);
    for pair in value.as_bytes().chunks_exact(2) {
        let high = hex_nibble(pair[0]).ok_or(QrcDecryptError::InvalidHex)?;
        let low = hex_nibble(pair[1]).ok_or(QrcDecryptError::InvalidHex)?;
        bytes.push((high << 4) | low);
    }
    if !bytes.len().is_multiple_of(8) {
        return Err(QrcDecryptError::MisalignedBlocks);
    }
    Ok(bytes)
}

const fn hex_nibble(value: u8) -> Option<u8> {
    match value {
        b'0'..=b'9' => Some(value - b'0'),
        b'a'..=b'f' => Some(value - b'a' + 10),
        b'A'..=b'F' => Some(value - b'A' + 10),
        _ => None,
    }
}

struct Des {
    subkeys: [u64; 16],
}

impl Des {
    fn new(key: [u8; 8], encrypt: bool) -> Self {
        let mut value = map_u64(u64::from_le_bytes(key), &KEY_PERMUTATION);
        let mut c = low_u32(value);
        let mut d = u32::try_from(value >> 32).expect("upper half is exactly 32 bits");
        let mut subkeys = [0; 16];

        for (round, shift) in KEY_ROUND_SHIFTS.into_iter().enumerate() {
            rotate_key_half(&mut c, shift);
            rotate_key_half(&mut d, shift);
            value = u64::from(d) << 32 | u64::from(c);
            let index = if encrypt { round } else { 15 - round };
            subkeys[index] = map_u64(value, &KEY_COMPRESSION);
        }
        Self { subkeys }
    }

    fn transform_bytes(&self, data: &mut [u8]) {
        debug_assert!(data.len().is_multiple_of(8));
        for block in data.chunks_exact_mut(8) {
            let mut bytes = [0; 8];
            bytes.copy_from_slice(block);
            block.copy_from_slice(
                &self
                    .transform_block(u64::from_le_bytes(bytes))
                    .to_le_bytes(),
            );
        }
    }

    fn transform_block(&self, data: u64) -> u64 {
        let mut state = map_u64(data, &INITIAL_PERMUTATION);
        for key in self.subkeys {
            state = des_round(state, key);
        }
        state = state.rotate_left(32);
        map_u64(state, &INVERSE_INITIAL_PERMUTATION)
    }
}

fn rotate_key_half(value: &mut u32, shift: u8) {
    let right = 28 - shift;
    *value = (*value << shift) | ((*value >> right) & 0xffff_fff0);
}

fn des_round(state: u64, key: u64) -> u64 {
    let high = u32::try_from(state >> 32).expect("upper half is exactly 32 bits");
    let low = low_u32(state);
    let expanded = map_u64(u64::from(high) << 32 | u64::from(high), &KEY_EXPANSION) ^ key;
    let substituted =
        LARGE_STATE_SHIFTS
            .into_iter()
            .enumerate()
            .fold(0_u32, |result, (index, shift)| {
                let sbox_index = ((expanded >> shift) & 0b11_1111) as usize;
                (result << 4) | u32::from(SBOXES[index][sbox_index])
            });
    let next_low = map_u32(substituted, &P_BOX) ^ low;
    u64::from(next_low) << 32 | u64::from(high)
}

fn map_u32(value: u32, table: &[u8]) -> u32 {
    let mut result = 0_u64;
    for (set, check) in table.iter().copied().enumerate() {
        map_bit(
            &mut result,
            u64::from(value),
            check,
            u8::try_from(set).expect("32-entry table index fits u8"),
        );
    }
    u32::try_from(result).expect("32-bit permutation result fits u32")
}

fn map_u64(value: u64, table: &[u8]) -> u64 {
    let midpoint = table.len() / 2;
    let mut low = 0_u64;
    let mut high = 0_u64;
    for (set, check) in table[..midpoint].iter().copied().enumerate() {
        map_bit(
            &mut low,
            value,
            check,
            u8::try_from(set).expect("permutation half index fits u8"),
        );
    }
    for (set, check) in table[midpoint..].iter().copied().enumerate() {
        map_bit(
            &mut high,
            value,
            check,
            u8::try_from(set).expect("permutation half index fits u8"),
        );
    }
    u64::from(low_u32(high)) << 32 | u64::from(low_u32(low))
}

fn low_u32(value: u64) -> u32 {
    u32::try_from(value & u64::from(u32::MAX)).expect("masked value fits u32")
}

fn map_bit(result: &mut u64, source: u64, check: u8, set: u8) {
    if bit_mask(check) & source != 0 {
        *result |= bit_mask(set);
    }
}

const fn bit_mask(index: u8) -> u64 {
    let index = index & 0x3f;
    if index < 32 {
        1_u64 << (31 - index)
    } else {
        1_u64 << (95 - index)
    }
}

#[cfg(test)]
mod tests {
    use super::{QrcDecryptError, decrypt_cloud_qrc};

    const SYNTHETIC_QRC: &str = "6447440FA5912BEC47EBDC0F7AB9DBF847898BC76ABCB709C0C54D9D6978ECB97215F4B28B51CCAE8B4EB4770A40E946F617E688A35972D20678A27250A2CC7A27B47B4F03BC55A3A2C612D6BB5D5E1F84A193DD1300931765FDCE14968B9672AC39037736BFCF7477FFB1FC1A30262A2642D946938797373D17F93807532D4521F920DE15943C1C159ECE086BD712BBD41B53DB6F9B3611440AD23536818A61FCDEA679DAB19A08";
    const SYNTHETIC_PLAINTEXT: &str = "<?xml version=\"1.0\" encoding=\"utf-8\"?><QrcInfos><LyricInfo LyricCount=\"1\"><Lyric_1 LyricType=\"1\" LyricContent=\"[ar:Project Fixture]&#10;[1000,800]Syn(1000,400)thetic(1400,400)&#10;[2200,0]\"/></LyricInfo></QrcInfos>";

    #[test]
    fn decrypts_independently_generated_synthetic_known_answer() {
        assert_eq!(
            decrypt_cloud_qrc(SYNTHETIC_QRC),
            Ok(SYNTHETIC_PLAINTEXT.into())
        );
    }

    #[test]
    fn rejects_malformed_ciphertext_without_echoing_it() {
        assert_eq!(decrypt_cloud_qrc(""), Err(QrcDecryptError::Empty));
        assert_eq!(decrypt_cloud_qrc("A"), Err(QrcDecryptError::OddHexLength));
        assert_eq!(decrypt_cloud_qrc("GG"), Err(QrcDecryptError::InvalidHex));
        assert_eq!(
            decrypt_cloud_qrc("AA"),
            Err(QrcDecryptError::MisalignedBlocks)
        );
        assert_eq!(
            decrypt_cloud_qrc("0000000000000000"),
            Err(QrcDecryptError::Decompress)
        );
    }
}

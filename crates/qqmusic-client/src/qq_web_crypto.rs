//! QQ Web request signature and ag-1 codec.
//!
//! The zzc/ag-1 compatibility algorithm is adapted from
//! jixunmoe/qmweb-sign at 15305a3cc39f80eb1646ab2bae46468231765736
//! under the MIT License. See /THIRD_PARTY_NOTICES.md.

use base64::{Engine as _, engine::general_purpose::STANDARD};
use ring::aead::{AES_128_GCM, Aad, LessSafeKey, Nonce, UnboundKey};
use sha1::{Digest as _, Sha1};

const PART_1_INDEXES: [usize; 7] = [23, 14, 6, 36, 16, 7, 19];
const PART_2_INDEXES: [usize; 8] = [16, 1, 32, 12, 19, 27, 8, 5];
const SCRAMBLE_VALUES: [u8; 20] = [
    89, 39, 179, 150, 218, 82, 58, 252, 177, 52, 186, 123, 120, 64, 242, 133, 143, 161, 121,
    179,
];
const REQUEST_KEY: [u8; 16] = [
    189, 48, 95, 16, 208, 255, 116, 182, 239, 84, 218, 184, 53, 181, 225, 207,
];
const RESPONSE_KEY: [u8; 21] = [
    122, 63, 140, 29, 94, 155, 47, 10, 108, 77, 126, 139, 31, 58, 92, 157, 14, 43, 111, 74, 129,
];

pub(crate) fn zzc_sign(payload: &str) -> String {
    const HEX: &[u8; 16] = b"0123456789ABCDEF";
    let digest = Sha1::digest(payload.as_bytes());
    let mut hex = [0_u8; 40];
    for (index, byte) in digest.iter().copied().enumerate() {
        hex[index * 2] = HEX[usize::from(byte >> 4)];
        hex[index * 2 + 1] = HEX[usize::from(byte & 0x0f)];
    }
    let part_1 = PART_1_INDEXES
        .iter()
        .map(|index| char::from(hex[*index]))
        .collect::<String>();
    let part_2 = PART_2_INDEXES
        .iter()
        .map(|index| char::from(hex[*index]))
        .collect::<String>();
    let scrambled = SCRAMBLE_VALUES
        .iter()
        .zip(digest.iter())
        .map(|(left, right)| left ^ right)
        .collect::<Vec<_>>();
    let middle = STANDARD
        .encode(scrambled)
        .chars()
        .filter(|character| !matches!(character, '\\' | '/' | '+' | '='))
        .collect::<String>();
    format!("zzc{part_1}{middle}{part_2}").to_ascii_lowercase()
}

fn request_key() -> Result<LessSafeKey, ()> {
    UnboundKey::new(&AES_128_GCM, &REQUEST_KEY)
        .map(LessSafeKey::new)
        .map_err(|_| ())
}

pub(crate) fn encode_ag1_request(payload: &str) -> Result<String, ()> {
    let mut nonce = [0_u8; 12];
    getrandom::fill(&mut nonce).map_err(|_| ())?;
    encode_ag1_request_with_nonce(payload, nonce)
}

fn encode_ag1_request_with_nonce(payload: &str, nonce: [u8; 12]) -> Result<String, ()> {
    let mut encrypted = payload.as_bytes().to_vec();
    request_key()?
        .seal_in_place_append_tag(
            Nonce::assume_unique_for_key(nonce),
            Aad::empty(),
            &mut encrypted,
        )
        .map_err(|_| ())?;
    let mut wire = Vec::with_capacity(12 + encrypted.len());
    wire.extend_from_slice(&nonce);
    wire.extend_from_slice(&encrypted);
    Ok(STANDARD.encode(wire))
}

pub(crate) fn decode_ag1_response(data: &[u8]) -> String {
    let decoded = data
        .iter()
        .enumerate()
        .map(|(index, byte)| byte ^ RESPONSE_KEY[index % RESPONSE_KEY.len()])
        .collect::<Vec<_>>();
    String::from_utf8_lossy(&decoded).into_owned()
}

#[cfg(test)]
pub(crate) fn decode_ag1_request_for_test(data: &[u8]) -> Result<String, ()> {
    let wire = STANDARD.decode(data).map_err(|_| ())?;
    let nonce: [u8; 12] = wire.get(..12).ok_or(())?.try_into().map_err(|_| ())?;
    let mut encrypted = wire.get(12..).ok_or(())?.to_vec();
    let plain = request_key()?
        .open_in_place(
            Nonce::assume_unique_for_key(nonce),
            Aad::empty(),
            &mut encrypted,
        )
        .map_err(|_| ())?;
    String::from_utf8(plain.to_vec()).map_err(|_| ())
}

#[cfg(test)]
pub(crate) fn encode_ag1_response_for_test(payload: &str) -> Vec<u8> {
    payload
        .as_bytes()
        .iter()
        .enumerate()
        .map(|(index, byte)| byte ^ RESPONSE_KEY[index % RESPONSE_KEY.len()])
        .collect()
}

#[cfg(test)]
mod tests {
    use super::{
        decode_ag1_request_for_test, decode_ag1_response, encode_ag1_request_with_nonce,
        encode_ag1_response_for_test, zzc_sign,
    };

    #[test]
    fn zzc_matches_the_pinned_mit_reference_vector() {
        assert_eq!(
            zzc_sign("123"),
            "zzcec1b555gzqzg7laztguyjl2bu20r6x1w50c55f60"
        );
    }

    #[test]
    fn ag1_request_round_trip_uses_the_exact_96_bit_nonce() {
        let payload = r#"{"comm":{"ct":24},"req_0":{"method":"AddSonglist"}}"#;
        let encoded =
            encode_ag1_request_with_nonce(payload, [0x5a; 12]).expect("fixture encryption");
        assert_eq!(
            decode_ag1_request_for_test(encoded.as_bytes()).expect("fixture decryption"),
            payload
        );
    }

    #[test]
    fn ag1_response_codec_matches_the_wire_xor_contract() {
        let payload = r#"{"code":0,"req_0":{"code":0}}"#;
        let encoded = encode_ag1_response_for_test(payload);
        assert_ne!(encoded, payload.as_bytes());
        assert_eq!(decode_ag1_response(&encoded), payload);
    }
}

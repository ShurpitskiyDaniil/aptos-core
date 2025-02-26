// Copyright (c) Aptos
// SPDX-License-Identifier: Apache-2.0

//! This module defines the physical storage schema for state value index, which is used
//! to access the state value directly without needing to walk through the JMT.
//!
//! An Index Key in this data set has 2 pieces of information:
//!     1. The state key
//!     2. The version associated with the key
//! The value associated with the key is nibble length, which combined with the state key and
//! version can give us access to the JMT leaf associated with corresponding key and version
//!
//!
//! //! ```text
//! |<---------key--------> |<-----value----->|
//! |  state_key, version  |   num of nibbles |
//! ```

use crate::schema::{ensure_slice_len_eq, ensure_slice_len_gt, STATE_VALUE_INDEX_CF_NAME};
use anyhow::Result;
use aptos_types::{state_store::state_key::StateKey, transaction::Version};
use byteorder::{BigEndian, ReadBytesExt, WriteBytesExt};
use schemadb::{
    define_schema,
    schema::{KeyCodec, ValueCodec},
};
use std::{io::Write, mem::size_of};

type Key = (StateKey, Version);

define_schema!(StateValueIndexSchema, Key, u8, STATE_VALUE_INDEX_CF_NAME);

impl KeyCodec<StateValueIndexSchema> for Key {
    fn encode_key(&self) -> Result<Vec<u8>> {
        let mut encoded = vec![];
        encoded.write_all(&self.0.encode()?)?;
        encoded.write_u64::<BigEndian>(self.1)?;
        Ok(encoded)
    }

    fn decode_key(data: &[u8]) -> Result<Self> {
        const VERSION_SIZE: usize = size_of::<Version>();

        ensure_slice_len_gt(data, VERSION_SIZE)?;
        let state_key_len = data.len() - VERSION_SIZE;
        let state_key: StateKey = StateKey::decode(&data[..state_key_len])?;
        let version = (&data[state_key_len..]).read_u64::<BigEndian>()?;
        Ok((state_key, version))
    }
}

impl ValueCodec<StateValueIndexSchema> for u8 {
    fn encode_value(&self) -> Result<Vec<u8>> {
        let mut encoded = vec![];
        encoded.write_u8(*self)?;
        Ok(encoded)
    }

    fn decode_value(data: &[u8]) -> Result<Self> {
        ensure_slice_len_eq(data, 1)?;
        Ok(data[0])
    }
}

#[cfg(test)]
mod test;

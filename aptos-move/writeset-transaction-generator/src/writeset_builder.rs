// Copyright (c) Aptos
// SPDX-License-Identifier: Apache-2.0

use anyhow::format_err;
use aptos_crypto::HashValue;
use aptos_state_view::StateView;
use aptos_types::{
    account_address::AccountAddress,
    account_config::{self, aptos_root_address},
    transaction::{ChangeSet, Script, Version},
};
use aptos_vm::{
    data_cache::RemoteStorage,
    move_vm_ext::{MoveVmExt, SessionExt, SessionId},
};
use move_core_types::{
    identifier::Identifier,
    language_storage::{ModuleId, TypeTag},
    resolver::MoveResolver,
    transaction_argument::convert_txn_args,
    value::{serialize_values, MoveValue},
};
use move_vm_types::gas_schedule::GasStatus;

pub struct GenesisSession<'r, 'l, S>(SessionExt<'r, 'l, S>);

impl<'r, 'l, S: MoveResolver> GenesisSession<'r, 'l, S> {
    pub fn exec_func(
        &mut self,
        module_name: &str,
        function_name: &str,
        ty_args: Vec<TypeTag>,
        args: Vec<Vec<u8>>,
    ) {
        self.0
            .execute_function(
                &ModuleId::new(
                    account_config::CORE_CODE_ADDRESS,
                    Identifier::new(module_name).unwrap(),
                ),
                &Identifier::new(function_name).unwrap(),
                ty_args,
                args,
                &mut GasStatus::new_unmetered(),
            )
            .unwrap_or_else(|e| {
                panic!(
                    "Error calling {}.{}: {}",
                    module_name,
                    function_name,
                    e.into_vm_status()
                )
            });
    }

    pub fn exec_script(&mut self, sender: AccountAddress, script: &Script) {
        self.0
            .execute_script(
                script.code().to_vec(),
                script.ty_args().to_vec(),
                convert_txn_args(script.args()),
                vec![sender],
                &mut GasStatus::new_unmetered(),
            )
            .unwrap()
    }

    fn disable_reconfiguration(&mut self) {
        self.exec_func(
            "Reconfiguration",
            "disable_reconfiguration",
            vec![],
            serialize_values(&vec![MoveValue::Signer(aptos_root_address())]),
        )
    }

    fn enable_reconfiguration(&mut self) {
        self.exec_func(
            "Reconfiguration",
            "enable_reconfiguration",
            vec![],
            serialize_values(&vec![MoveValue::Signer(aptos_root_address())]),
        )
    }
    pub fn set_aptos_version(&mut self, version: Version) {
        self.exec_func(
            "AptosVersion",
            "set_version",
            vec![],
            serialize_values(&vec![
                MoveValue::Signer(aptos_root_address()),
                MoveValue::U64(version),
            ]),
        )
    }
}

pub fn build_changeset<S: StateView, F>(state_view: &S, procedure: F) -> ChangeSet
where
    F: FnOnce(&mut GenesisSession<RemoteStorage<S>>),
{
    let move_vm = MoveVmExt::new().unwrap();
    let session_out = {
        let state_view_storage = RemoteStorage::new(state_view);
        // TODO: specify an id by human and pass that in.
        let genesis_id = HashValue::zero();
        let mut session = GenesisSession(
            move_vm.new_session(&state_view_storage, SessionId::genesis(genesis_id)),
        );
        session.disable_reconfiguration();
        procedure(&mut session);
        session.enable_reconfiguration();
        session
            .0
            .finish()
            .map_err(|err| format_err!("Unexpected VM Error: {:?}", err))
            .unwrap()
    };

    session_out
        .into_change_set(&mut ())
        .map_err(|err| format_err!("Unexpected VM Error: {:?}", err))
        .unwrap()
}

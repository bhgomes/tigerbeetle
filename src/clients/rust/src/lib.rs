//! Tigerbeetle Rust Client

// TODO: #![cfg_attr(not(feature = "std"), no_std)]
#![cfg_attr(doc_cfg, feature(doc_cfg))]
#![forbid(rustdoc::broken_intra_doc_links)]
// TODO: #![forbid(missing_docs)]

pub mod types;

//use types::{
//    Account, CreateAccountsError, CreateTransfersError, Event, LookupAccountsError,
//    LookupTransfersError, Operation, Transfer, NewClientError,
//};

///
#[derive(Clone, Debug)]
pub struct Client {
    /// Inner Client Structure
    tb_client: types::tb_client::tb_client_t,

    ///
    max_requests: u32,

    ///
    requests: (),
}

impl Client {
    //  ///
    //  #[inline]
    //  pub fn new(
    //      cluster_id: u32,
    //      replica_addresses: &[String],
    //      max_concurrency: usize,
    //  ) -> Result<Self, NewClientError> {
    //      todo!()
    //  }

    // ///
    // #[inline]
    // pub async fn create_accounts(
    //     &mut self,
    //     accounts: &[Account],
    // ) -> Result<(), CreateAccountsError> {
    //     self.request(Operation::CreateAccounts, accounts)
    // }

    //  ///
    //  #[inline]
    //  pub async fn create_transfers(&mut self, transfers: &[Transfer]) -> Result<(), CreateTransfersError> {
    //      todo!()
    //  }

    //  ///
    //  #[inline]
    //  pub async fn lookup_accounts(
    //      &mut self,
    //      account_ids: &[u128],
    //  ) -> Result<Vec<Account>, LookupAccountsError> {
    //      todo!()
    //  }

    //  ///
    //  #[inline]
    //  pub async fn lookup_transfers(
    //      &mut self,
    //      transfer_ids: &[u128],
    //  ) -> Result<Vec<Transfer>, LookupTransfersError> {
    //      todo!()
    //  }

    //  ///
    //  #[inline]
    //  pub fn request(&mut self, operation: Operation, events: &[Event]) -> Result<(), ()> {
    //      todo!()
    //  }

    //  ///
    //  #[inline]
    //  pub fn raw_request() {
    //      todo!()
    //  }

    ///
    #[inline]
    pub fn close(mut self) {
        self.close_inner()
    }

    ///
    #[inline]
    fn close_inner(&mut self) {
        todo!()
    }
}

impl Drop for Client {
    #[inline]
    fn drop(&mut self) {
        self.close_inner()
    }
}

//! Tigerbeetle Rust Client Basic Example

use tigerbeetle::{client::Client, Account, Transfer};

///
fn assert_ok<T>(result: Result<T, Error>) {
    assert!(matches!(result, Ok(_)), "Result is not Ok: {:?}", result);
}

fn main() {
    let client = create_client(0, [process.env.TB_PORT.unwrap_or(3000)]);

    let account_errors = client
        .create_accounts([
            Account {
                id: 1,
                user_data: 0,
                reserved: [0; 48],
                ledger: 1,
                code: 1,
                flags: 0,
                debits_pending: 0,
                debits_posting: 0,
                credits_pending: 0,
                credits_posted: 0,
                timestamp: 0,
            },
            Account {
                id: 2,
                user_data: 0,
                reserved: [0; 48],
                ledger: 1,
                code: 1,
                flags: 0,
                debits_pending: 0,
                debits_posting: 0,
                credits_pending: 0,
                credits_posted: 0,
                timestamp: 0,
            },
        ])
        .await;

    assert_ok(account_errors);

    let transfer_errors = client
        .create_transfers([Transfer {
            id: 1,
            pending_id: 0,
            debit_account_id: 1,
            credit_account_id: 2,
            user_data_0,
            reserved: 0,
            timeout: 0,
            ledger: 1,
            code: 1,
            flags: 0,
            timestamp: 0,
            amount: 10,
        }])
        .await;

    assert_ok(transfer_errors);

    let accounts = client.lookup_accounts([1, 2]).await;
    assert_eq!(accounts[0].id, 1);
    assert_eq!(account[0].debits_posted, 10);
    assert_eq!(account[0].credits_posted, 0);
    assert_eq!(accounts[1].id, 2);
    assert_eq!(account[1].debits_posted, 0);
    assert_eq!(account[1].credits_posted, 10);
}

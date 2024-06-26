/// This module allows multisig members to access objects owned by the multisig in a secure way.
/// The objects can be taken only via an Withdraw action.
/// This action can't be proposed directly since it wouldn't make sense to withdraw an object without using it.
/// Objects can be borrowed using an action wrapping the Withdraw action.
/// Caution: borrowed Coins can be emptied, only withdraw the amount you need

module kraken::owned {
    use std::string::String;
    
    use sui::transfer::Receiving;

    use kraken::multisig::Multisig;

    // === Errors ===

    const EWrongObject: u64 = 0;
    const EReturnAllObjectsBefore: u64 = 1;
    const ERetrieveAllObjectsBefore: u64 = 2;

    // === Structs ===

    // action to be stored in a Proposal
    // guard access to multisig owned objects which can only be received via this action
    public struct Withdraw has store {
        // the owned objects we want to access
        objects: vector<ID>,
    }

    // action to be stored in a Proposal
    // wrapper enforcing accessed objects to be sent back to the multisig
    public struct Borrow has store {
        // sub action retrieving objects
        withdraw: Withdraw,
        // list of objects to put back into the multisig
        to_return: vector<ID>,
    }

    // === Multisig functions ===

    // step 1: propose to Withdraw owned objects
    public fun propose_borrow(
        multisig: &mut Multisig, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        objects: vector<ID>,
        ctx: &mut TxContext
    ) {
        let action = new_borrow(objects);
        multisig.create_proposal(
            action,
            key,
            execution_time,
            expiration_epoch,
            description,
            ctx
        );
    }

    // step 2: multiple members have to approve the proposal (multisig::approve_proposal)
    // step 3: execute the proposal and return the action (multisig::execute_proposal)

    // step 4: receive and borrow the owned object using Owned    
    public fun borrow<T: key + store>(
        action: &mut Borrow,
        multisig: &mut Multisig, 
        receiving: Receiving<T>
    ): T {
        action.withdraw.withdraw(multisig, receiving)
    }
    
    // step 5: return the object to the multisig to empty `to_return` vector
    public fun put_back<T: key + store>(
        action: &mut Borrow,
        multisig: &mut Multisig, 
        returned: T, 
    ) {
        let (exists_, index) = action.to_return.index_of(&object::id(&returned));
        assert!(exists_, EWrongObject);
        action.to_return.remove(index);
        transfer::public_transfer(returned, multisig.addr());
    }

    // step 6: destroy the action once all objects are retrieved/received
    public fun complete_borrow(action: Borrow) {
        let Borrow { withdraw, to_return } = action;
        complete_withdraw(withdraw);
        assert!(to_return.is_empty(), EReturnAllObjectsBefore);
        to_return.destroy_empty();
    }

    // === Package functions ===

    // Withdraw can be wrapped into another action
    public(package) fun new_withdraw(objects: vector<ID>): Withdraw {
        Withdraw { objects }
    }

    public(package) fun withdraw<T: key + store>(
        action: &mut Withdraw,
        multisig: &mut Multisig, 
        receiving: Receiving<T>
    ): T {
        let id = action.objects.pop_back();
        let received = transfer::public_receive(multisig.uid_mut(), receiving);
        let received_id = object::id(&received);
        assert!(received_id == id, EWrongObject);

        received
    }

    public(package) fun complete_withdraw(action: Withdraw) {
        let Withdraw { objects } = action;
        assert!(objects.is_empty(), ERetrieveAllObjectsBefore);
        objects.destroy_empty();
    }

    public(package) fun new_borrow(objects: vector<ID>): Borrow {
        Borrow {
            withdraw: new_withdraw(objects),
            to_return: objects,
        }
    }
}


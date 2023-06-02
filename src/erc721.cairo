// compile => cargo run --bin starknet-compile -- erc721.cairo
// Current repo can not be compiled because lack of independence
#[contract]
mod ERC721 {

    // same like msg.sender in Solidity, return type is ContractAddress
    use starknet::get_caller_address;
    use starknet::contract_address_const;
    use starknet::ContractAddress;
    // contract address type to felt type
    use starknet::ContractAddressIntoFelt252;
    // felt to int. eg, 1.into()
    use traits::Into;
    // 2 lines below can make is_zero() of ContractAddress usable to assert if the address is 0
    use zeroable::Zeroable;
    use array::ArrayTrait;

    struct Storage {
        name: felt252,
        symbol: felt252,
        owners: LegacyMap::<u256, ContractAddress>,
        balances: LegacyMap::<ContractAddress, u256>,
        token_approvals: LegacyMap::<u256, ContractAddress>,
        // (owner, operator)
        operator_approvals: LegacyMap::<(ContractAddress, ContractAddress), bool>,
        token_name: LegacyMap::<u256, felt252>, // token_id => token_name
    }

    #[event]
    fn Approval(owner: ContractAddress, to: ContractAddress, token_id: u256) {}

    #[event]
    fn Transfer(from: ContractAddress, to: ContractAddress, token_id: u256) {}

    #[event]
    fn ApprovalForAll(owner: ContractAddress, operator: ContractAddress, approved: bool) {}

    #[constructor]
    fn constructor(_name: felt252, _symbol: felt252) {
        name::write(_name);
        symbol::write(_symbol);
        _mint(starknet::contract_address_const::<0x058c19CCF47AFd7acC6db057FE4c6676168b130281C315007075fCD732503B7D>(), 0.into());
        _mint(starknet::contract_address_const::<0x058c19CCF47AFd7acC6db057FE4c6676168b130281C315007075fCD732503B7D>(), 1.into());
    }

    #[external]
    fn set_approval_for_all(operator: ContractAddress, approved: bool) {
        _set_approval_for_all(get_caller_address(), operator, approved);
    }

    fn _set_approval_for_all(owner: ContractAddress, operator: ContractAddress, approved: bool) {
        // ContractAddress equation is not supported so into() is used here
        assert(owner != operator, 'ERC721: approve to caller');
        operator_approvals::write((owner, operator), approved);
        ApprovalForAll(owner, operator, approved);
    }

    #[external]
    fn approve(to: ContractAddress, token_id: u256) {
        let owner = _owner_of(token_id);
        // Unlike Solidity, require is not supported, only assert can be used
        // The max length of error msg is 31 or there's an error
        assert(to != owner, 'Approval to current owner');
        // || is not supported currently so we use | here
        assert(get_caller_address() == owner | is_approved_for_all(owner, get_caller_address()), 'Not token owner');
        _approve(to, token_id);
    }

    
    fn _approve(to: ContractAddress, token_id: u256) {
        token_approvals::write(token_id, to);
        Approval(owner_of(token_id), to, token_id);
    }

    #[external]
    fn transfer_from(from: ContractAddress, to: ContractAddress, token_id: u256) {
        assert(_is_approved_or_owner(from, token_id), 'Caller is not owner or appvored');
        _transfer(from, to, token_id);
    }

    
    fn _exists(token_id: u256) -> bool {
        !_owner_of(token_id).is_zero()
    }

    
    fn _owner_of(token_id: u256) -> ContractAddress {
        owners::read(token_id)
    }

    fn _mint(to: ContractAddress, token_id: u256) {
        assert(!to.is_zero(), 'ERC721: mint to 0');
        assert(!_exists(token_id), 'ERC721: already minted');
        _beforeTokenTransfer(contract_address_const::<0>(), to, token_id, 1.into());
        assert(!_exists(token_id), 'ERC721: already minted');

        balances::write(to, balances::read(to) + 1.into());
        owners::write(token_id, to);
        // contract_address_const::<0>() => means 0 address
        Transfer(contract_address_const::<0>(), to, token_id);

        _afterTokenTransfer(contract_address_const::<0>(), to, token_id, 1.into());
    }
    
    fn _burn(token_id: u256) {
        let owner = owner_of(token_id);
        _beforeTokenTransfer(owner, contract_address_const::<0>(), token_id, 1.into());
        let owner = owner_of(token_id);
        token_approvals::write(token_id, contract_address_const::<0>());

        balances::write(owner, balances::read(owner) - 1.into());
        owners::write(token_id, contract_address_const::<0>());
        Transfer(owner, contract_address_const::<0>(), token_id);

        _afterTokenTransfer(owner, contract_address_const::<0>(), token_id, 1.into());
    }

    
    fn _require_minted(token_id: u256) {
        assert(_exists(token_id), 'ERC721: invalid token ID');
    }
    
    fn _is_approved_or_owner(spender: ContractAddress, token_id: u256) -> bool {
        let owner = owners::read(token_id);
        // || is not supported currently so we use | here
        spender == owner 
            | is_approved_for_all(owner, spender) 
            | get_approved(token_id) == spender
    }

    
    fn _transfer(from: ContractAddress, to: ContractAddress, token_id: u256) {
        assert(from == owner_of(token_id), 'Transfer from incorrect owner');
        assert(!to.is_zero(), 'ERC721: transfer to 0');

        _beforeTokenTransfer(from, to, token_id, 1.into());

        token_approvals::write(token_id, contract_address_const::<0>());

        balances::write(from, balances::read(from) - 1.into());
        balances::write(to, balances::read(to) + 1.into());

        owners::write(token_id, to);

        Transfer(from, to, token_id);

        _afterTokenTransfer(from, to, token_id, 1.into());
    }

    #[view]
    fn is_approved_for_all(owner: ContractAddress, operator: ContractAddress) -> bool {
        operator_approvals::read((owner, operator))
    }

    #[view]
    fn get_approved(token_id: u256) -> ContractAddress {
        _require_minted(token_id);
        token_approvals::read(token_id)
    }

    #[view]
    fn token_uri(token_id: u256) -> Array<felt252> {
        //_require_minted(token_id);
        let mut a = _base_uri();
        a.append('/');
        format_number(a, token_id.into())
    }

    fn format_number(mut array_to_incr: Array<felt252>, number_to_format: u256) -> Array<felt252> {
        if (number_to_format/10_u256 == 0_u256) {
            array_to_incr.append(number_to_format.low.into());
            return array_to_incr;
        }
        let first_number = get_first_number(number_to_format);
        format_number(array_to_incr, number_to_format-first_number*get_digit_amount(number_to_format))
    }

    fn get_first_number(number: u256) -> u256 {
        if (number/10_u256 < 10_u256) {
            return number;
        }
        get_first_number(number/10_u256)
    }

    fn get_digit_amount(number: u256) -> u256 {
        if (number/10_u256 == 0_u256) {
            return 1_u256;
        }
        get_digit_amount(number/10_u256) + 1_u256
    }

    #[view]
    fn _base_uri() -> Array<felt252> {
        let mut a = ArrayTrait::new();
        a.append('ipfs://bafybeib');
        a.append('ycmzrgn6hxrnfre');
        a.append('jkjoemjjewz73y7');
        a.append('uhkkf3urk7vxmzg');
        a.append('jk6h3q');
        a
    }

    #[view]
    fn balance_of(account: ContractAddress) -> u256 {
        assert(!account.is_zero(), 'ERC721: address zero');
        balances::read(account)
    }

    #[view]
    fn owner_of(token_id: u256) -> ContractAddress {
        let owner = _owner_of(token_id);
        // both are OK!
        // assert(owner.into() != contract_address_const::<0>().into(), 'ERC721: invalid token ID');
        assert(!owner.is_zero(), 'ERC721: invalid token ID');
        owner
    }

    #[view]
    fn get_name() -> felt252 {
        name::read()
    }

    #[view]
    fn get_symbol() -> felt252 {
        symbol::read()
    }

    fn _beforeTokenTransfer(
        from: ContractAddress, 
        to: ContractAddress, 
        first_token_id: u256, 
        batch_size: u256
    ) {}

    fn _afterTokenTransfer(
        from: ContractAddress, 
        to: ContractAddress, 
        first_token_id: u256, 
        batch_size: u256
    ) {}

}
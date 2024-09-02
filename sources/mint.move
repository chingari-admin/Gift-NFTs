module GiftNfts::mint{
    // use std::features;
    use aptos_token_objects::collection;
    use aptos_token_objects::token;
    //use aptos_token_objects::royalty;
    use aptos_framework::object::{Self};
    use std::signer;
    use std::string::{String};
    use std::option::{Self};
    use std::error;
    
    //use std::account;
    use aptos_framework::account::{Self,SignerCapability};
    use std::ed25519;

    const EINVALID_OWNER_PROOF: u64=1;
    const EINVALID_ADMIN: u64=2;
    const EINVALID_SENDER_AND_TO_ADDRESS_ARE_SAME: u64=3;

    struct AdminAccount has key{
        signer_cap: SignerCapability
        
    }

    struct Management has key {
        admin: address,
        public_key: ed25519::ValidatedPublicKey,
    }

    struct MintProofChallenge has drop{
        minter_sequence_number: u64,
        minter_address: address,
        token_name: String,
    }

    // inline fun collection_object(creator: &signer, name: &String): Object<AptosCollection> {
    //     let collection_addr = collection::create_collection_address(&signer::address_of(creator), name);
    //     object::address_to_object<AptosCollection>(collection_addr)
    // }

    
    fun verify_proof_of_knowledge(minter_addr: address,token_name: String,public_key: ed25519::ValidatedPublicKey,
    proof: vector<u8>){
        let sequence_number=aptos_framework::account::get_sequence_number(minter_addr);

        let proof_challenge=MintProofChallenge{
            minter_sequence_number: sequence_number,
            minter_address: minter_addr,
            token_name: token_name
        };

        let signature=ed25519::new_signature_from_bytes(proof);
        let unvalidated_public_key=ed25519::public_key_to_unvalidated(&public_key);
        assert!(ed25519::signature_verify_strict_t(&signature,&unvalidated_public_key,proof_challenge),error::permission_denied(EINVALID_OWNER_PROOF));
    }

    fun acquire_signer(
        sender: &signer,
        common_account: address,
        token_name: String,
        proof: vector<u8>
    ): signer acquires AdminAccount, Management {
        let sender_addr = signer::address_of(sender);
   
        let management= borrow_global<Management>(common_account);
        let resource = borrow_global<AdminAccount>(management.admin);
        verify_proof_of_knowledge(sender_addr,token_name,management.public_key,proof);
        account::create_signer_with_capability(&resource.signer_cap)
    }

    public entry fun create_admin_account(admin: &signer, seed: vector<u8>,pk_bytes: vector<u8>){
        assert!(@admin==signer::address_of(admin),error::permission_denied(EINVALID_ADMIN));
        let (resource_signer, signer_cap) = account::create_resource_account(admin, seed);
        let public_key=std::option::extract(&mut ed25519::new_validated_public_key_from_bytes(pk_bytes));
        move_to(
            &resource_signer,
            Management{
                admin: signer::address_of(admin),
                public_key: public_key,
            }
        );

        move_to(
            admin,
            AdminAccount{
                signer_cap: signer_cap
            }
        );

    }

    public entry fun set_public_key(admin: &signer, common_address: address,pk_bytes: vector<u8>) acquires Management{
        let public_key=std::option::extract(&mut ed25519::new_validated_public_key_from_bytes(pk_bytes));
        let management_resource=borrow_global_mut<Management>(common_address);
        assert!(management_resource.admin==signer::address_of(admin),error::permission_denied(EINVALID_ADMIN));
        management_resource.public_key=public_key;
    }


    public entry fun resource_mint_collection(sender: &signer, common_account: address,
     name: String,
    description: String,
    uri: String,
    proof: vector<u8>) acquires AdminAccount,Management{
        let common_signer=acquire_signer(sender,common_account,name,proof);

        mint_collection_unlimited(&common_signer,name,description,uri);
    }


    public entry fun resource_mint_token_memo(sender: &signer, common_account: address,
    to:address,
    collection: String,
     name: String,
    description: String,
    uri: String,
    proof: vector<u8>,
    _memo: String) acquires AdminAccount,Management{
        resource_mint_token(sender,common_account,to,collection,name,description,uri,proof);
    }

    public entry fun resource_mint_token(sender: &signer, common_account: address,
    to:address,
    collection: String,
     name: String,
    description: String,
    uri: String,
    proof: vector<u8>) acquires AdminAccount,Management{
        assert!(signer::address_of(sender)!=to,error::permission_denied(EINVALID_SENDER_AND_TO_ADDRESS_ARE_SAME));
        
        let common_signer=acquire_signer(sender,common_account,name,proof);

        mint_to(&common_signer,to,collection,description,name,uri);
    }

    public entry fun mint_collection_unlimited(  creator: &signer,
    name: String,
    description: String,
    uri: String,
    ){
        collection::create_unlimited_collection(
            creator,// creator: &signer,
            description,// description: String,
            name,// name: String,
            option::none(),// royalty: Option<Royalty>,
            uri,// uri: String,
        );
    }

    public entry fun mint_to(
        creator: &signer,
        to:address,
        collection: String,
        description: String,
        name: String,
        uri: String,
        // property_keys: vector<String>,
        // property_types: vector<String>,
        // property_values: vector<vector<u8>>,
    ) {
        let creator_addr=signer::address_of(creator);
        let token_creation_num = account::get_guid_next_creation_num(creator_addr);
        
        // let constructor_ref = 
        //let expected_royalty = royalty::create(50, 1000, creator_addr);
        // if (features::auids_enabled()) {
        //     token::create(
        //         creator,
        //         collection,
        //         description,
        //         name,
        //         option::some(expected_royalty),
        //         uri
        //     );
        // } else {
            token::create_from_account(
                creator,
                collection,
                description,
                name,
                //option::some(expected_royalty),
                option::none(),
                uri,
            );
        // };

        // let collection = collection_object(creator, &collection);
        
        // let transfer_ref = object::generate_transfer_ref(&constructor_ref);
        //let token_addr = token::create_token_address(&creator_addr, &collection, &name);
        let token_addr=object::create_guid_object_address(creator_addr, token_creation_num);
        // let token= object::address_to_object<token::Token>(token_addr);
        // object::transfer(creator, token, to);
        transfer_token(creator,token_addr,to);
    }
    
    public entry fun transfer_token(owner: &signer, token_address: address, to: address){
        let token= object::address_to_object<token::Token>(token_address);
        object::transfer(owner, token, to);
    }
    
    //#[test_only]
    //use aptos_token_objects::collection::{Self};
    #[test_only]
    use std::string::{Self};

     #[test_only]
    use std::debug;

    #[test_only]
    use std::bcs;
    
    #[test_only]
    use aptos_std::from_bcs;

    #[test_only]
    use std::hash;

    #[test_only]
    use std::vector;

    #[test_only]
    use aptos_framework::account::create_account_for_test;
    
    #[test_only]
    public fun set_up_test(origin_account: &signer,
    _resource_account: &signer,
    admin_public_key: &ed25519::ValidatedPublicKey) {
        create_account_for_test(signer::address_of(origin_account));
        //aptos_framework::resource_account::create_resource_account(origin_account,vector::empty<u8>(),vector::empty<u8>());

        let bytes=bcs::to_bytes(&signer::address_of(origin_account));
        vector::append(&mut bytes,vector::empty<u8>());
        vector::push_back(&mut bytes, 255);
        let seed_address=from_bcs::to_address(hash::sha3_256(bytes));
        debug::print<address>(&seed_address);

        let pk_bytes=ed25519::validated_public_key_to_bytes(admin_public_key);
        //set_admin_public_key(origin_account, pk_bytes,string::utf8(b"Admin set memo"));
        create_admin_account(origin_account,b"",pk_bytes);

    }

    #[test(creator = @0x123)]
    fun test_create_and_transfer(creator: &signer)  {
        let creator_address=signer::address_of(creator);
        account::create_account_for_test(creator_address);
        let collection_name = string::utf8(b"collection name");
        let token_name = string::utf8(b"token name");
        let token_creation_num = account::get_guid_next_creation_num(creator_address);
        // let expected_royalty = option::none();
        // collection::create_fixed_collection(
        //     creator,
        //     string::utf8(b"collection description"),
        //     10_000_000,
        //     collection_name,
        //     option::none(),
        //     string::utf8(b"collection uri"),
        // );
        mint_collection_unlimited(creator,collection_name,string::utf8(b"collection description"),string::utf8(b"collection uri"));

        
        mint_to(creator,@0x345,collection_name,string::utf8(b"token description"),token_name,string::utf8(b"collection uri"));
        //let token_addr = token::create_token_address(&creator_address, &collection_name, &token_name);
        let token_addr=object::create_guid_object_address(creator_address, token_creation_num);
        let token = object::address_to_object<token::Token>(token_addr);
        assert!(object::owner(token) == @0x345, 1);

    }

    #[test(origin_account=@0xcafe,resource_account=@0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5, nft_receiver1=@0x123,nft_receiver2=@0x234)]
    fun test_resource_create_and_transfer(origin_account: signer, resource_account: signer,
     nft_receiver1:signer,nft_receiver2 : signer) acquires AdminAccount, Management{
        let (admin_sk,admin_pk)=ed25519::generate_keys();
        set_up_test(&origin_account, &resource_account,&admin_pk );
        
        create_account_for_test(signer::address_of(&nft_receiver1));
        create_account_for_test(signer::address_of(&nft_receiver2));
        let token_title=string::utf8(b"Test Token 1");
        let collection_title=string::utf8(b"Test Collection 1");

        let collection_proof=MintProofChallenge{
            minter_sequence_number: aptos_framework::account::get_sequence_number(signer::address_of(&nft_receiver1)),
            minter_address: signer::address_of(&nft_receiver1),
            token_name: collection_title,
        };
        let sig=ed25519::sign_struct(&admin_sk, collection_proof);

        resource_mint_collection(&nft_receiver1,signer::address_of(&resource_account),collection_title,string::utf8(b"collection description"),string::utf8(b"collection uri"),ed25519::signature_to_bytes(&sig));

        let (admin_sk_2,admin_pk_2)=ed25519::generate_keys();
        let pk_bytes_2=ed25519::validated_public_key_to_bytes(&admin_pk_2);
        set_public_key(&origin_account,signer::address_of(&resource_account),pk_bytes_2);
        

        let token_proof=MintProofChallenge{
            minter_sequence_number: aptos_framework::account::get_sequence_number(signer::address_of(&nft_receiver1)),
            minter_address: signer::address_of(&nft_receiver1),
            token_name: token_title,
        };
        let sig_2=ed25519::sign_struct(&admin_sk_2, token_proof);

        let token_creation_num = account::get_guid_next_creation_num(signer::address_of(&resource_account));
        resource_mint_token(&nft_receiver1,signer::address_of(&resource_account),signer::address_of(&nft_receiver2),
        collection_title,token_title,string::utf8(b"token description"),string::utf8(b"token uri"),ed25519::signature_to_bytes(&sig_2));

        let token_addr=object::create_guid_object_address(signer::address_of(&resource_account), token_creation_num);
        let token = object::address_to_object<token::Token>(token_addr);
        assert!(object::owner(token) == signer::address_of(&nft_receiver2), 1);

       
        
    }

}
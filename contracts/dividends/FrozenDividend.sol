pragma solidity ^0.4.23;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "@evolutionland/common/contracts/interfaces/ISettingsRegistry.sol";
import "@evolutionland/common/contracts/SettingIds.sol";

contract FrozenDividend is Ownable, SettingIds{
    using SafeMath for *;

    event DepositKTON(address indexed _from, uint256 _value);

    event WithdrawKTON(address indexed _to, uint256 _value);

    event Income(address indexed _from, uint256 _value);

    event OnDividendsWithdraw(address indexed _user, uint256 _ringValue);

    uint256 constant internal magnitude = 2**64;

    bool private singletonLock = false;

    mapping(address => uint256) public ktonBalances;

    mapping(address => int256) internal ringPayoutsTo;

    uint256 public ktonSupply = 0;

    uint256 internal ringProfitPerKTON;

    ISettingsRegistry public registry;

    /*
     * Modifiers
     */
    modifier singletonLockCall() {
        require(!singletonLock, "Only can call once");
        _;
        singletonLock = true;
    }

    constructor() public {
        // initializeContract
    }

    function initializeContract(ISettingsRegistry _registry) public singletonLockCall {
        owner = msg.sender;

        registry = _registry;
    }

    function tokenFallback(address _from, uint256 _value, bytes _data) public {
        address ring = registry.addressOf(SettingIds.CONTRACT_RING_ERC20_TOKEN);
        address kton = registry.addressOf(SettingIds.CONTRACT_KTON_ERC20_TOKEN);

        if (msg.sender == ring) {
            // trigger settlement
            incomeRING(_value);
        }

        if (msg.sender == kton) {
            depositKTON(_value);
        }
    }

    function incomeRING(uint256 _ringValue) internal {
        if (ktonSupply > 0) {
            ringProfitPerKTON = ringProfitPerKTON.add(
                _ringValue.mul(magnitude).div(ktonSupply)
                );
        }

        emit Income(msg.sender, _ringValue);
    }

    function depositKTON(uint256 _ktonValue) internal {
        ktonBalances[msg.sender] = ktonBalances[msg.sender].add(ktonBalances[msg.sender]);
        ktonSupply = ktonSupply.add(_ktonValue);

        int256 _updatedPayouts = (int256) (ringProfitPerKTON * _ktonValue);
        ringPayoutsTo[msg.sender] += _updatedPayouts;

        emit DepositKTON(msg.sender, _ktonValue);
    }

    function withdrawKTON(uint256 _ktonValue) internal {
        require(_ktonValue <= ktonBalances[msg.sender], "Withdraw KTON amount should not larger than balance.");

        ktonBalances[msg.sender] = ktonBalances[msg.sender].sub(_ktonValue);
        ktonSupply = ktonSupply.sub(_ktonValue);

        // update dividends tracker
        int256 _updatedPayouts = (int256) (ringProfitPerKTON * _ktonValue);
        ringPayoutsTo[msg.sender] -= _updatedPayouts;

        emit WithdrawKTON(msg.sender, _ktonValue);
    }

    function withdrawDividends()public
    {
        // setup data
        address _customerAddress = msg.sender;
        uint256 _dividends = dividendsOf(_customerAddress);
        
        // update dividend tracker
        ringPayoutsTo[_customerAddress] += (int256) (_dividends * magnitude);

        address ring = registry.addressOf(SettingIds.CONTRACT_RING_ERC20_TOKEN);
        ERC20(ring).transfer(_customerAddress, _dividends);
        
        // fire event
        emit OnDividendsWithdraw(_customerAddress, _dividends);
    }

    function dividendsOf(address _customerAddress) public view returns(uint256)
    {
        return (uint256) ((int256)(ringProfitPerKTON * ktonBalances[_customerAddress]) - ringPayoutsTo[_customerAddress]) / magnitude;
    }

    /**
     * Retrieve the total token supply.
     */
    function totalKTON() public view returns(uint256)
    {
        return ktonSupply;
    }

}
// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IPermitPost, Permit} from "permitpost/interfaces/IPermitPost.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {OrderValidator} from "../lib/OrderValidator.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {
    ResolvedOrder,
    OrderInfo,
    OrderStatus,
    TokenAmount,
    Signature,
    Output
} from "../interfaces/ReactorStructs.sol";

/// @notice Reactor for simple limit orders
contract BaseReactor {
    using OrderValidator for mapping(bytes32 => OrderStatus);
    using OrderValidator for OrderInfo;

    address public immutable permitPost;

    mapping(bytes32 => OrderStatus) public orderStatus;

    constructor(address _permitPost) {
        permitPost = _permitPost;
    }

    /// @notice validates and fills an order, marking it as filled
    function fill(
        ResolvedOrder memory order,
        Signature calldata sig,
        bytes32 orderHash,
        address fillContract,
        bytes calldata fillData
    ) internal {
        order.info.validate();
        orderStatus.updateFilled(orderHash);
        IPermitPost(permitPost).saltTransferFrom(
            Permit({
                token: order.input.token,
                spender: address(this),
                maxAmount: order.input.amount,
                deadline: order.info.deadline
            }),
            order.info.offerer,
            fillContract,
            order.input.amount,
            orderHash,
            sig
        );

        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        resolvedOrders[0] = order;
        IReactorCallback(fillContract).reactorCallback(resolvedOrders, fillData);

        // transfer output tokens to their respective recipients
        for (uint256 i = 0; i < order.outputs.length; i++) {
            Output memory output = order.outputs[i];
            ERC20(output.token).transferFrom(
                fillContract,
                output.recipient,
                output.amount
            );
        }
    }

    function fillBatch(
        ResolvedOrder[] memory orders,
        Signature[] memory signatures,
        bytes32[] memory orderHashes,
        address fillContract,
        bytes calldata fillData
    ) internal {
        for (uint i = 0; i < orders.length; i++) {
            orders[i].info.validate();
            orderStatus.updateFilled(orderHashes[i]);
            IPermitPost(permitPost).saltTransferFrom(
                Permit({
                    token: orders[i].input.token,
                    spender: address(this),
                    maxAmount: orders[i].input.amount,
                    deadline: orders[i].info.deadline
                }),
                orders[i].info.offerer,
                fillContract,
                orders[i].input.amount,
                orderHashes[i],
                signatures[i]
            );
        }

        IReactorCallback(fillContract).reactorCallback(orders, fillData);

        // transfer output tokens to their respective recipients
        for (uint256 i = 0; i < orders.length; i++) {
            for (uint256 j = 0; j < orders[i].outputs.length; j++) {
                Output memory output = orders[i].outputs[j];
                ERC20(output.token).transferFrom(
                    fillContract,
                    output.recipient,
                    output.amount
                );
            }
        }
    }
}

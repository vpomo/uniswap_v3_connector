// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";


interface ITicketNft is IERC721Enumerable {

    function setBaseTokenURI(string calldata _baseTokenURI) external;

    function setStakeContract(bool _enable, address _contract) external;

    function mint(address _owner) external returns (uint256);

    function burn(uint256 tokenId) external returns (bool);

    function tokensOfOwner(address _user) external view returns (uint256[] memory);

    function tokensCount() external view returns (uint256);
}

# Cetus CLMM Vault Template

This is a template file that demonstrates how to convert Cetus CLMM positions into LP coins for distribution to users.

It adopts a decoupled design pattern where users can obtain LP coins after adding liquidity, and when users burn LP coins, they can receive the corresponding proportion of liquidity.

Position management is handled by administrators using a centralized administrator permission design. The administrator address can customize strategies to adjust the Position's Tick Range, withdraw positions, or deposit positions back.

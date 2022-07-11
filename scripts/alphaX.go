package scripts

import (
	"math/big"
)

func calculateAlphaX(reserve0SnapShot *big.Int, reserve1SnapShot *big.Int, reserve0Execution *big.Int, reserve1Execution *big.Int) *big.Float {
	executionSpot := new(big.Float).Quo(new(big.Float).SetInt(reserve0Execution), new(big.Float).SetInt(reserve1Execution))
	snapshotSpot := new(big.Float).Quo(new(big.Float).SetInt(reserve0SnapShot), new(big.Float).SetInt(reserve1SnapShot))

	delta := new(big.Float).Abs(new(big.Float).Sub(new(big.Float).Quo(executionSpot, snapshotSpot), new(big.Float).SetInt(big.NewInt(1))))

	partial := new(big.Float).Mul(new(big.Float).SetInt(reserve0SnapShot), new(big.Float).SetInt(reserve1SnapShot))

	numeratorPartial1 := new(big.Float).Mul(new(big.Float).Sqrt(partial), new(big.Float).Sqrt(new(big.Float).SetInt(reserve0SnapShot)))
	numeratorPartial2 := new(big.Float).Sqrt(new(big.Float).Add(new(big.Float).Mul(delta, new(big.Float).SetInt(reserve1SnapShot)), new(big.Float).SetInt(reserve1SnapShot)))
	numerator := new(big.Float).Sub(new(big.Float).Mul(numeratorPartial1, numeratorPartial2), new(big.Float).Mul(new(big.Float).SetInt(reserve0SnapShot), new(big.Float).SetInt(reserve1SnapShot)))
	exp := big.NewInt(0).Exp(big.NewInt(2), big.NewInt(64), nil)
	return new(big.Float).Mul(new(big.Float).Quo(numerator, new(big.Float).SetInt(reserve1SnapShot)), new(big.Float).SetInt(exp))
}

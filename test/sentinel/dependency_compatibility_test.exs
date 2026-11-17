defmodule Sentinel.DependencyCompatibilityTest do
  use ExUnit.Case, async: true

  test "Ratio interoperates with the Decimal version required by Ecto" do
    for {value, numerator, denominator} <- [
          {"1.25", 5, 4},
          {"-0.125", -1, 8},
          {"1E+3", 1000, 1},
          {"0", 0, 1}
        ] do
      assert Ratio.new(Decimal.new(value)) == Ratio.new(numerator, denominator)
    end

    assert Numbers.add(Ratio.new(1, 4), Decimal.new("0.5")) == Ratio.new(3, 4)
    assert Numbers.div(Decimal.new("1.5"), Ratio.new(3, 4)) == Ratio.new(2)
    assert Numbers.mult(Decimal.new("1.5"), Ratio.new(2)) == Ratio.new(3)
  end
end

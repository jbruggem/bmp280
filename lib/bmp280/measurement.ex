defmodule BMP280.Measurement do
  @moduledoc """
  One sensor measurement report

  The temperature, pressure and relative humidity measurements are computed
  directly from the sensor. All other values are derived.
  """
  defstruct [:temperature_c, :pressure_pa, :altitude_m, :humidity_rh, :dew_point_c]

  @type t :: %__MODULE__{
          temperature_c: number(),
          pressure_pa: number(),
          altitude_m: number(),
          humidity_rh: number() | :unknown,
          dew_point_c: number() | :unknown
        }
end

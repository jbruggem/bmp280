defmodule BMP280 do
  use GenServer

  alias BMP280.{Calc, Calibration, Measurement, Transport}
  @sea_level_pa 101_325

  @moduledoc """
  Read temperature and pressure measurements from a [Bosch
  BMP280](https://www.bosch-sensortec.com/products/environmental-sensors/pressure-sensors/pressure-sensors-bmp280-1.html)
  sensor in Elixir.
  """

  @doc """
  Start a new GenServer for interacting with a BMP280
  """
  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg)
  end

  @doc """
  Read the current temperature, pressure, altitude
  """
  @spec read(GenServer.server()) :: {:ok, Measurement.t()} | {:error, any()}
  def read(server) do
    GenServer.call(server, :read)
  end

  @doc """
  Update the sea level pressure estimate

  The sea level pressure should be specified in Pascals. The estimate
  is used for altitude calculations.
  """
  @spec update_sea_level_pressure(GenServer.server(), number()) :: :ok
  def update_sea_level_pressure(server, new_estimate) do
    GenServer.call(server, {:update_sea_level, new_estimate})
  end

  @doc """
  Force the altitude to a known value

  Altitude calculations depend on the accuracy of the sea level pressure estimate. Since
  the sea level pressure changes based on the weather, it needs to be kept up to date
  or altitude measurements can be pretty far off. Another way to set the sea level pressure
  is to report a known altitude. Call this function with the current altitude in meters.
  """
  @spec force_altitude(GenServer.server(), number()) :: :ok | {:error, any()}
  def force_altitude(server, altitude_m) do
    GenServer.call(server, {:force_altitude, altitude_m})
  end

  @impl GenServer
  def init([]) do
    {:ok, transport} = Transport.open("i2c-1")

    state = %{transport: transport, calibration: nil, sea_level_pa: @sea_level_pa}
    {:ok, state, {:continue, :continue}}
  end

  @impl GenServer
  def handle_continue(:continue, state) do
    new_state =
      state
      |> send_enable()
      |> read_calibration()

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_call(:read, _from, state) do
    rc =
      case read_raw_samples(state) do
        {:ok, raw_pressure, raw_temperature} ->
          {:ok,
           Calc.raw_to_measurement(
             state.calibration,
             state.sea_level_pa,
             raw_temperature,
             raw_pressure
           )}

        error ->
          error
      end

    {:reply, rc, state}
  end

  def handle_call({:update_sea_level, new_estimate}, _from, state) do
    {:reply, :ok, %{state | sea_level_pa: new_estimate}}
  end

  def handle_call({:force_altitude, altitude_m}, _from, state) do
    case read_raw_samples(state) do
      {:ok, raw_pressure, raw_temperature} ->
        {:ok,
         m =
           Calc.raw_to_measurement(
             state.calibration,
             state.sea_level_pa,
             raw_temperature,
             raw_pressure
           )}

        sea_level = Calc.sea_level_pressure(m.pressure_pa, altitude_m)

        {:reply, :ok, %{state | sea_level_pa: sea_level}}

      error ->
        {:reply, error, state}
    end
  end

  defp send_enable(state) do
    # normal
    mode = 3
    # x2 oversampling
    osrs_t = 2
    # x16 oversampling
    osrs_p = 5
    ctrl_meas_register = 0xF4

    :ok =
      Transport.write(
        state.transport,
        ctrl_meas_register,
        <<osrs_t::size(3), osrs_p::size(3), mode::size(2)>>
      )

    state
  end

  defp read_calibration(state) do
    {:ok, raw} = Transport.read(state.transport, 0x88, 24)

    %{state | calibration: Calibration.from_binary(raw)}
  end

  defp read_raw_samples(state) do
    case Transport.read(state.transport, 0xF7, 6) do
      {:ok, <<pressure::size(20), _::size(4), temp::size(20), _::size(4)>>} ->
        {:ok, pressure, temp}

      {:error, _reason} = error ->
        error
    end
  end
end
defmodule Membrane.FramerateConverter do
  @moduledoc """
  Element converts video to target constant frame rate, by dropping and duplicating frames as necessary
  Input video may have constant or variable frame rate.
  Element expects each frame to be received in separate buffer.
  Additionally, presentation timestamps must be passed in each buffer's metadata.
  """

  use Bunch
  use Membrane.Filter

  alias Membrane.Buffer
  alias Membrane.Caps.Video.Raw

  require Membrane.Logger

  def_options framerate: [
                spec: tuple(),
                default: {30, 1},
                description: """
                Target framerate.
                """
              ]

  def_output_pad :output,
    caps: {Raw, aligned: true}

  def_input_pad :input,
    caps: {Raw, aligned: true},
    demand_unit: :buffers

  @impl true
  def handle_init(%__MODULE__{} = options) do
    state =
      options
      |> Map.from_struct()
      |> Map.merge(%{
        last_payload: nil,
        last_metadata: nil,
        target_pts: 0
      })

    {:ok, state}
  end

  @impl true
  def handle_demand(:output, size, :buffers, _ctx, state) do
    {{:ok, demand: {:input, size}}, state}
  end

  @impl true
  def handle_process(
        :input,
        %{payload: payload, metadata: metadata} = buffer,
        _ctx,
        %{last_payload: nil} = state
      ) do
    unless Map.has_key?(metadata, :pts), do: raise("cannot cut stream without pts")

    state = %{
      state
      | target_pts: metadata.pts,
        last_metadata: metadata,
        last_payload: payload
    }

    {{:ok, [buffer: {:output, buffer}, redemand: :output]}, bump_target_pts(state)}
  end

  @impl true
  def handle_process(
        :input,
        %{payload: payload, metadata: metadata},
        _ctx,
        %{last_payload: _last_payload} = state
      ) do
    unless Map.has_key?(metadata, :pts), do: raise("cannot cut stream without pts")

    {buffers, state} = create_new_frames(metadata, payload, state)
    {{:ok, [buffer: {:output, buffers}, redemand: :output]}, state}
  end

  @impl true
  def handle_caps(:input, caps, _context, %{framerate: framerate} = state) do
    {{:ok, caps: {:output, %{caps | framerate: framerate}}, redemand: :output}, state}
  end

  defp bump_target_pts(state) do
    use Ratio
    %{target_pts: pts, framerate: {num, denom}} = state
    target_pts = pts + Ratio.new(denom * Membrane.Time.second(), num)
    %{state | target_pts: target_pts}
  end

  defp create_new_frames(metadata, payload, state, buffers \\ []) do
    use Ratio

    if Ratio.gt?(state.target_pts, metadata.pts) do
      state = %{
        state
        | last_metadata: metadata,
          last_payload: payload
      }

      {Enum.reverse(buffers), state}
    else
      dist_right = metadata.pts - state.target_pts
      dist_left = state.target_pts - state.last_metadata.pts

      if Ratio.lte?(dist_left, dist_right) do
        buffer = %Buffer{
          payload: state.last_payload,
          metadata: %{state.last_metadata | pts: state.target_pts}
        }

        state = bump_target_pts(state)
        create_new_frames(metadata, payload, state, [buffer | buffers])
      else
        buffer = %Buffer{
          payload: payload,
          metadata: %{metadata | pts: state.target_pts}
        }

        state = bump_target_pts(state)
        create_new_frames(metadata, payload, state, [buffer | buffers])
      end
    end
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    {{:ok, end_of_stream: :output}, state}
  end
end

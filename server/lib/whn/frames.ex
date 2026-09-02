defmodule Whn.Frames do
  @moduledoc """
  Last-frame extraction for image-to-video chaining.

  Downloads a clip, grabs a frame 0.25s before its end with the local
  ffmpeg, uploads the jpg to fal storage, and returns the hosted URL —
  the `image_url` the next segment animates from.
  """

  @doc """
  Extracts the last frame of `video_url` and returns its hosted URL.

  Accepts an http(s) URL or a local file path (the path branch keeps the
  function testable and script-friendly without an HTTP server).
  """
  @spec last_frame(String.t()) :: {:ok, String.t()} | {:error, term()}
  def last_frame(video_url) do
    unique = System.unique_integer([:positive])
    in_path = Path.join(System.tmp_dir!(), "whn_clip_#{unique}.mp4")
    out_path = Path.join(System.tmp_dir!(), "whn_frame_#{unique}.jpg")

    try do
      with {:ok, clip_path} <- fetch(video_url, in_path),
           :ok <- extract(clip_path, out_path) do
        Whn.Fal.upload(out_path)
      end
    after
      File.rm(in_path)
      File.rm(out_path)
    end
  end

  defp fetch(source, in_path) do
    if File.exists?(source) do
      {:ok, source}
    else
      case Req.get(source, into: File.stream!(in_path)) do
        {:ok, %Req.Response{status: 200}} -> {:ok, in_path}
        {:ok, %Req.Response{status: status}} -> {:error, {:download_failed, status}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # The AAC track can outlast the video stream, and -sseof measures from
  # container duration — an overhang > ~0.25s seeks past the last video
  # frame ("Nothing was written into output file"). Retry once from -1s,
  # still inside the clip's final second; a second failure propagates.
  defp extract(clip_path, out_path) do
    case run_ffmpeg(clip_path, out_path, "-0.25") do
      {:error, {:ffmpeg, _exit_code, _output}} -> run_ffmpeg(clip_path, out_path, "-1")
      ok -> ok
    end
  end

  defp run_ffmpeg(clip_path, out_path, sseof) do
    args = ["-y", "-sseof", sseof, "-i", clip_path, "-frames:v", "1", "-q:v", "3", out_path]

    case System.cmd("ffmpeg", args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, exit_code} -> {:error, {:ffmpeg, exit_code, output}}
    end
  end
end

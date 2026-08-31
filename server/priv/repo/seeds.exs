# Seeds the Lagos Wahala launch episode:
#
#     mix run priv/repo/seeds.exs
#
# Idempotent: re-running skips the insert when an episode with the same
# title already exists.

import Ecto.Query

attrs = Whn.Seed.salary_just_entered()

unless Whn.Repo.exists?(from e in Whn.Schemas.Episode, where: e.title == ^attrs.title) do
  {:ok, _episode} = Whn.Store.create_episode(attrs)
end

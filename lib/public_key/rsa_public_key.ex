defmodule Preprocessing.PublicKey.RSAPublicKey do
  use Preprocessing.Record,
    record_id: :RSAPublicKey,
    module: :public_key,
    filepath: "include/public_key.hrl"

end

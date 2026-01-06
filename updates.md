so the judges pointed my in this direction, might give me an idea about matrix sizes
"Building your Score
The top 32 (as of September 19, 2025) node scores of each epoch enter into the validator list for the next epoch. Validators that are already in the current epoch and make it to the next epoch receive emissions.

Validators who made top 32 but drop out in next epoch receive no emissions, we are currently thinking about how to make this more forgiving to encourage adoption and lower validator risk. If you have suggestions please share.

To build your score you need to produce solutions that are seeded with your validators key. The current protocol level parse of the seed is here https://github.com/amadeus-robot/node/blob/main/ex/lib/bic/sol.ex and as of September 19, 2025 its built like so:


Copy
<<
  epoch::32-little, 
  segment_vr_hash::32-binary,
  node_pk::48-binary,
  node_pop::96-binary,
  solver_pk::48-binary,         # (optional) hint who solved the sol
  nonce::12-binary
>>

seed = <<
  Consensus.chain_epoch()::32-little, 
  Consensus.chain_segment_vr_hash()::32-binary,
  Application.fetch_env!(:ama, :trainer_pk)::48-binary, 
  Application.fetch_env!(:ama, :trainer_pop)::96-binary,
  Application.fetch_env!(:ama, :trainer_pk)::48-binary,
  :crypto.strong_rand_bytes(12)::12-binary
>>

b = Blake3.new()
Blake3.update(b, seed)
<<
   matrix_a::binary-size(16*50240),
   matrix_b::binary-size(50240*16)
>> = Blake3.finalize_xof(b, 16*50240 + 50240*16)
c = MatrixMul.multiply(matrix_a, matrix_b) |> MatrixMul.map_to_binary()
solution = seed <> c

diff_bits = Consensus.chain_diff_bits()
<<leading_zeros::size(diff_bits), _::bitstring>> = hash = Blake3.hash(solution)
if leading_zeros == 0 do
  IO.puts "congratulations, broadcast this now to the network to increase score"
  tx_packed = TX.build(Application.fetch_env!(:ama, :trainer_sk), 
    "Epoch", "submit_sol", [solution])
  TXPool.insert_and_broadcast(tx_packed)
end"

also this on validating score "Risks of Validating
Once the new epoch starts and your node score is in the top 32:


Copy
API.Epoch.score()

[
  ["7DXyX5siLBPbkwhW2aaV4WRuLAHu7LTn2BJFNvprZ5wt9jtrXXusrys7qKmJdBhx1n", 82307],
  ["6u6Ym7mx3aqajGZHqdYP4eF8pNrFHx9vCEWNRa71ijTQhxSqTnjsR8RJc4DYTYUuxo", 9504],
  ["5zU13Q4iNrcxYenX5oUU8h7YAzM7XqQAzMe9fHs9dyxf58HMnA4JMX9vC7q5GiGpKa", 9493],
  ["6L9Tuur76iEd862SoERbuhHFFjWh2V5kMLAZhdKL5aYiQivCNfYYniPxogu4yLwpQ9", 9178],
  ["6bntFSNoGRQtaJkqD9czp9RxkiajVYg9mdnYd6h8gV3CFZKUd4eC6vCGWWfXHjMUXX", 9098],
  ["6V7zuE9Ci4RHWVDZxrKDK6sKR6QMEHdW7BrwadTR5N8dqyvE1VYEEGq9gWapPdy461", 9042],
  ["71botgABuPbNq8rfTtcEB4yrpo8SfLP22eos6cHTr2okmraU8TrFk7yzSBMhFfhRnq", 8997],
  ["6AK24JHCvsSvrVd9e1nntUd6ViKKq96cfnQpfvSDYivxt6MFvsGMb6DHRkQmP3huZU", 8783],
  ["7eQUenPHLRKvYGgCFS5CU1Si6qa4HnQps4uxXiQo587xu8aBHRXZRFpUPzNSAM2Fdj", 8693],
  ["667rUL2QG8EjedXzrmuHuBVoACQqmYgGxi65KR7JwJE1m9DXMXtrZ9hwSqcawvZrXo", 8598],
  ["7pGZFZpfJbUf8NwqSw84cRvNGabvDdd2SafxvNdTUh7Peus2S1tBv21ETiq46Xg4kb", 8338],
  ["6Z1xwWG5fNudY81gfL695DfJWh3uhmGvNsv2Q6aUotZudUHPqLeAjCxeDt5WXj7MBz", 8316],
  ["7VgGc6ZfALjrRyK6fxQeV6gZeeGpByoPx1uU5gdb1y1DVgLxyBFSa9vSQQFVhiprEp", 8202],
  ["6H3pRBo5snb5qNaehR9DBcm57YCvPaBDED5sRQ1LT7oSZuBpnib7VdsduHR2ojweFz", 8137],
  ["5qYZD8HVJzXX4UJDCe6gHdAu4or2jWdnkUX1ZLdGxBx3cKj6NkbXNz46CGxMjqyuL1", 8088],
  ["6ddsvp1auJ2zWqDwFJdoHvijEsHyXLfS2yFnxmyCBfgU7PsNRoeMgJSRhdforShBk5", 8077],
  ["7SswepNgUigEMiaxtVPHCU8pCJjNXAqp1ZZgEaqZGAtZZThqmg9JnjPPJ4fzJTHhHY", 8070],
  ["7nZ1tCQtfMBeFeJ8DGYX55QkWB7CtNpDfKgoehXrmUetVN68bAPNSzLYU76Bkz8kDv", 8025],
  ["7WH7ZHYwQZ6Fq3E95gzMohb2qpb4rbisFC4dtnWyQeheu6EgrbnpGHBc1mkzYbxkqb", 8015],
  ["6PAzwkAhjNPFrXDBE2Ew9YovvAZ3Z3abFEA6xFuRAgRDT2dsNyxDvrLLX7HVQwWht7", 7968],
  ["7FM7CE9wLpbFn317a7LcPvTRCcBx4jPb4NMmnM9zngo42JNK9aA1SETBufE6VkWaFj", 7952],
  ["5wXoFWTZAfrGZEyL2TzWGr2XQGSgdqbEbTGTWdhX9ciNEyh8yJoNWV7zBbWP2YcYYY", 7932],
  ["6YCDJ4f6dD8c5WuxDRp82ZYdho2Ha5qSeFTAZ3688y485hzH1WKViWwtFXm2qKdQEu", 7912],
  ["7SGTxaLStDPbLKnjcXC1fqN3xaGBs4oFEPVa6UVDwt5N63C7US4vf8wP9hB4p9Fdku", 7674],
  ["6yGYBgPmnvRfL8PuEECxkzpjCkdYwyTUP5abeqzKBB7BYfb2nU3YkUzC1KBNLwJRFd", 7605],
  ["78LByD8m22fAkAUxmpWf67WihHCeHX3SW2URN5H7zN2gqBdDy86LrKVxU9NR7DgCdK", 7590],
  ["5nooK1aeaUdD84oFsjUymzCiHRWNHzD6NBY5CSrZgSFNRwQUj7h3jA9gf62FcPPRWb", 7484],
  ["7HmEZ2zBKAaky3pfa3BjNiqDMoFgdzBpdkZfM5fH96hh8DhWE8nwpSPFE5KHMMaAmG", 7348],
  ["6PBwYc68quDCZFvi3qDwVHwEWWHUasAYZtbwzm6RX189pLXR7m8G3gDCNRMmVxxYJY", 7339],
  ["5t1jmA1tc68UFrBBfyGFJ6DUEpXUfUAMUfd65YqzfMkX7TcG2MvcNvoWMEyVh4tuYq", 7151],
  ["5kfTrgNrVFzkGAkQXDsPTreinAyPEE9szp8jvkBv44UnyHjpEZLm1xWpNNvLMSHCg9", 6998],
  ["6bmQpVDCyPBj3eNQ4Bz7zjGCC52rZ2PgtBANazbkESPVjxoHyGkJuPmmyB15ikekTH", 4904],
  ["72F3MbVLuUzxALsXAsTEJptYFGL9ewrHFhktZCGvj7JhWXnKJScpVqbbVTAEvU9Tok", 167],
  ["77PbahMBp91VnyQsBc3f59JvEiGoSuS6JUUtYmm1i3XZHxYyekgNoaoifJ5NLHA7sJ", 139]
]
You make it as validator into the next epoch. Your goal now is to produce entries on-time within the 500ms window until the epoch ends.

If you fail to produce an entry on-time or are stalling the network by producing late entries you are candidate for slashing. 

If you:

Over the last 10 entries your average slot time is higher than 700ms 

Do not produce an entry when it is your slot within 8seconds

Any validator can now call an on-chain special meeting and produce the proof plus agenda with the topic to vote for your removal, if consensus from other validators is reached via voting you are immediately dropped from the epoch and forfeit all accumulated score, any further calculations at epoch-end count your score as if it was 0. 

We are thinking to make this less harsh as there has been cases where honest nodes were being attacked and illegally DOSed to bring them offline and make candidates for slashing out of them. The benefit was their score was removed from the calculation of the emission so the attacker got a bigger piece for themselves at epoch end."


so this is meant to work on testnet so if you could wite it up properly i would love that "Connect to Testnet0
Testnet0 is available on:

TESTNET RPC https://testnet.ama.one/

TESTNET testnet.ama.one

TESTNET 46.4.179.184

Remember: Do not use your mainnet keys to interact with the testnet.

To connect the explorer or wallet on Testnet0 you need to redirect the nodes.amadeus.bot RPC to point to the testnet RPC. The easiest way to do this is via hosts file by adding an extra line


Copy
vim /etc/hosts
46.4.179.184 nodes.amadeus.bot
Another way is via host resolver in chrome


Copy
--host-resolver-rules="MAP nodes.amadeus.bot testnet.ama.one"
Next your browser when opening the explorer or wallet will give an SSL error so open a new Chrome profile dropping all security checks:


Copy
mkdir -p /tmp/chrome_testnet0

google-chrome  --user-data-dir="/tmp/chrome_testnet0" \
--no-first-run --no-default-browser-check \
--ignore-certificate-errors --disable-web-security \
--unsafely-treat-insecure-origin-as-secure=https://nodes.amadeus.bot

[OPTIONAL] if you did not use hosts file
--host-resolver-rules="MAP nodes.amadeus.bot testnet.ama.one"
Now you can open the following URLs in that isolated browser profile and all will work

https://ama-explorer.ddns.net/  

https://wallet.ama.one/"

also in the example for deploying an instance in koyeb they use the tenstorret image "ghcr.io/tenstorrent/tt-xla/tt-xla-ird-ubuntu-22-04:latest" i wonder if its worth using this 
Thanks

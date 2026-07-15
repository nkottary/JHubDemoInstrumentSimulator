module InstrumentSimulator

using HTTP, JSON3, Dates, Random
using Pkg: TOML

const TS_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS.sss"
format_ts(t::DateTime) = Dates.format(t, TS_FORMAT)

# Other services in this deployment sit behind an authenticating proxy, so
# outgoing requests need a bearer token. The token lives in the Julia
# package server auth file for whichever server JULIA_PKG_SERVER points at.
function auth_header()
    server = get(ENV, "JULIA_PKG_SERVER", "")
    isempty(server) && return Pair{String,String}[]
    path = joinpath(homedir(), ".julia", "servers", server, "auth.toml")
    isfile(path) || return Pair{String,String}[]
    token = get(TOML.parsefile(path), "access_token", nothing)
    token === nothing && return Pair{String,String}[]
    return ["Authorization" => "Bearer $token"]
end

struct SimConfig
    instrument_id::String
    dbservice_url::String
    interval::Float64
    amplitude::Float64
    frequency::Float64
    noise_std::Float64
    baseline::Float64
end

function config_from_env()
    return SimConfig(
        get(ENV, "INSTRUMENT_ID", "inst-1"),
        get(ENV, "DBSERVICE_URL", "https://dbservice.apps.nightly.juliahub.dev"),
        parse(Float64, get(ENV, "INTERVAL_SECONDS", "0.5")),
        parse(Float64, get(ENV, "AMPLITUDE", "10.0")),
        parse(Float64, get(ENV, "FREQUENCY_HZ", "0.05")),
        parse(Float64, get(ENV, "NOISE_STD", "0.5")),
        parse(Float64, get(ENV, "BASELINE", "20.0")),
    )
end

# baseline + sine wave + gaussian noise, meant to stand in for a physical
# sensor signal (e.g. a slowly cycling temperature or pressure reading)
next_value(cfg::SimConfig, elapsed_seconds::Float64) =
    cfg.baseline + cfg.amplitude * sin(2π * cfg.frequency * elapsed_seconds) + cfg.noise_std * randn()

function send_reading(cfg::SimConfig, timestamp::DateTime, value::Float64)
    body = JSON3.write((instrument_id = cfg.instrument_id, timestamp = format_ts(timestamp), value = value))
    headers = ["Content-Type" => "application/json"; auth_header()]
    try
        HTTP.post(cfg.dbservice_url * "/ingest", headers, body; readtimeout = 5)
        return true
    catch e
        @warn "failed to send reading to DBService" exception = (e, catch_backtrace())
        return false
    end
end

function main()
    cfg = config_from_env()
    @info "InstrumentSimulator starting" instrument_id = cfg.instrument_id dbservice_url = cfg.dbservice_url interval = cfg.interval
    t_start = time()
    while true
        elapsed = time() - t_start
        value = next_value(cfg, elapsed)
        ts = now()
        if send_reading(cfg, ts, value)
            @info "sent reading" instrument_id = cfg.instrument_id timestamp = format_ts(ts) value = round(value, digits = 3)
        end
        sleep(cfg.interval)
    end
end

end # module InstrumentSimulator

local assert = require("luassert")
local spy = require("luassert.spy")
local mock = require("luassert.mock")

-- Mock the required modules
local logger_mock = mock(require("parrot.logger"), true)
local utils_mock = mock(require("parrot.utils"), true)

-- Load the Perplexity class
local Perplexity = require("parrot.provider.perplexity")

describe("Perplexity", function()
  local perplexity

  before_each(function()
    perplexity = Perplexity:new("https://api.perplexity.ai/chat/completions", "test_api_key")
    -- Reset mocks
    logger_mock.error:clear()
    logger_mock.debug:clear()
  end)

  describe("process_onexit", function()
    it("should log an error message when there's an API error", function()
      local input = {
        "",
        "",
        "",
        " 401 Authorization Required ",
        " openresty/1.25.3.1", "",
        "",
      }

      perplexity:process_onexit(input)

      assert.spy(logger_mock.error).was_called_with(
        "Perplexity - message: 401 Authorization Required"
      )
    end)

    it("should not log anything for successful responses", function()
      local input = { "Success" }

      perplexity:process_onexit(input)

      assert.spy(logger_mock.error).was_not_called()
    end)
  end)

  describe("process_stdout", function()
    it("should extract content from a valid chat.completion.chunk response", function()
      local input = '{"id":"chatcmpl-123","object":"chat.completion.chunk","created":1721142785,"model":"llama-3-8b-instruct","choices":[{"index":0,"delta":{"content":" Assistant"},"finish_reason":null}]}'

      local result = perplexity:process_stdout(input)

      assert.equals(" Assistant", result)
    end)

    it("should handle responses without content", function()
      local input = '{"id":"chatcmpl-123","object":"chat.completion.chunk","created":1721142785,"model":"llama-3-8b-instruct","choices":[{"index":0,"delta":{},"finish_reason":null}]}'

      local result = perplexity:process_stdout(input)

      assert.is_nil(result)
    end)

    it("should return nil for non-matching responses", function()
      local input = '{"type":"other_response"}'

      local result = perplexity:process_stdout(input)

      assert.is_nil(result)
    end)

    it("should handle invalid JSON gracefully", function()
      local input = "invalid json"

      local result = perplexity:process_stdout(input)

      assert.is_nil(result)
      assert.spy(logger_mock.debug).was_called()
    end)
  end)

  describe("preprocess_payload", function()
    it("should trim whitespace from message content", function()
      local payload = {
        messages = {
          { role = "user", content = "  Hello, Perplexity!  " },
          { role = "assistant", content = " How can I help?  " }
        }
      }

      local result = perplexity:preprocess_payload(payload)

      assert.equals("Hello, Perplexity!", result.messages[1].content)
      assert.equals("How can I help?", result.messages[2].content)
    end)

    it("should filter payload parameters", function()
      utils_mock.filter_payload_parameters.returns({ filtered = true })

      local payload = { messages = {}, temperature = 0.7, invalid_param = "test" }

      local result = perplexity:preprocess_payload(payload)

      assert.is_true(result.filtered)
      assert.spy(utils_mock.filter_payload_parameters).was_called()
    end)
  end)

  describe("verify", function()
    it("should return true for a valid API key", function()
      assert.is_true(perplexity:verify())
    end)

    it("should return false and log an error for an invalid API key", function()
      perplexity.api_key = ""
      assert.is_false(perplexity:verify())
      assert.spy(logger_mock.error).was_called()
    end)

    it("should return false and log an error for an unresolved API key", function()
      perplexity.api_key = { unresolved = true }
      assert.is_false(perplexity:verify())
      assert.spy(logger_mock.error).was_called()
    end)
  end)

  describe("add_system_prompt", function()
    it("should add a system prompt to messages if provided", function()
      local messages = {
        { role = "user", content = "Hello" }
      }
      local sys_prompt = "You are a helpful assistant."

      local result = perplexity:add_system_prompt(messages, sys_prompt)

      assert.equals(2, #result)
      assert.same({ role = "system", content = sys_prompt }, result[1])
    end)

    it("should not add a system prompt if empty", function()
      local messages = {
        { role = "user", content = "Hello" }
      }
      local sys_prompt = ""

      local result = perplexity:add_system_prompt(messages, sys_prompt)

      assert.equals(1, #result)
      assert.same(messages, result)
    end)
  end)

  describe("check", function()
    it("should return true for supported models", function()
      assert.is_true(perplexity:check({ model = "llama-3-8b-instruct" }))
      assert.is_true(perplexity:check({ model = "mixtral-8x7b-instruct" }))
    end)

    it("should return false for unsupported models", function()
      assert.is_false(perplexity:check({ model = "unsupported-model" }))
    end)

    it("should handle model as a string or table", function()
      assert.is_true(perplexity:check("llama-3-8b-instruct"))
      assert.is_true(perplexity:check({ model = "llama-3-8b-instruct" }))
    end)
  end)

  describe("curl_params", function()
    it("should return correct curl parameters", function()
      local expected = {
        "https://api.perplexity.ai/chat/completions",
        "-H",
        "authorization: Bearer test_api_key",
        "content-type: text/event-stream",
      }

      local result = perplexity:curl_params()

      assert.same(expected, result)
    end)
  end)

  describe("set_model", function()
    it("should not modify any state", function()
      local initial_state = vim.deepcopy(perplexity)
      perplexity:set_model("some_model")
      assert.same(initial_state, perplexity)
    end)
  end)
end)
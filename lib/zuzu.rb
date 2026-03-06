# frozen_string_literal: true

# Zuzu — JRuby desktop framework for local-first agentic apps.
#
# Author:   Abhishek Parolkar <apac.abhi@gmail.com>
# License:  MIT
# Homepage: https://github.com/parolkar/zuzu

require 'zuzu/version'
require 'zuzu/config'
require 'zuzu/store'
require 'zuzu/agent_fs'
require 'zuzu/memory'
require 'zuzu/llm_client'
require 'zuzu/llamafile_manager'
require 'zuzu/tool_registry'
require 'zuzu/tools/file_tool'
require 'zuzu/tools/shell_tool'
require 'zuzu/tools/web_tool'
require 'zuzu/agent'
require 'zuzu/channels/base'
require 'zuzu/channels/in_app'
require 'zuzu/channels/whatsapp'
require 'zuzu/app'

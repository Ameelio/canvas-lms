# frozen_string_literal: true

#
# Copyright (C) 2026 - present Ameelio.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.

module Kratos
  class Engine < ::Rails::Engine
    isolate_namespace Kratos

    config.root = __dir__

    initializer "kratos.register", after: :load_config_initializers do |app|
      app.config.auth_providers << "Kratos::Provider"
    end
  end
end

# require_relative "config/routes"

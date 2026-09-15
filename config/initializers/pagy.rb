require "pagy/extras/overflow"

Pagy::DEFAULT[:limit] = 25
Pagy::DEFAULT[:overflow] = :last_page # a stale page number shows the last page, not an error
Pagy::DEFAULT.freeze

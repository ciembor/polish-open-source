FROM docker.io/library/ruby:3.4-slim

ENV APP_HOME=/app \
    BUNDLE_WITHOUT=development:test \
    PORT=9293 \
    RACK_ENV=production

WORKDIR ${APP_HOME}

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libsqlite3-0 \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN bundle config set without "${BUNDLE_WITHOUT}" \
    && bundle install --jobs=4 --retry=3

COPY . .
RUN mkdir -p db log tmp

EXPOSE 9293

CMD ["bundle", "exec", "rackup", "--host", "0.0.0.0", "--port", "9293"]

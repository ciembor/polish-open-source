FROM docker.io/library/ruby:4.0.5-slim-bookworm

ARG APP_UID=1000
ARG APP_GID=1000

ENV APP_HOME=/app \
    BUNDLE_APP_CONFIG=/app/tmp/bundle \
    BUNDLE_WITHOUT=development:test \
    HOME=/app/tmp \
    PORT=9293 \
    RACK_ENV=production \
    TMPDIR=/app/tmp

WORKDIR ${APP_HOME}

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential ca-certificates libsqlite3-0 pkg-config \
    && groupadd --gid "${APP_GID}" app \
    && useradd --uid "${APP_UID}" --gid app --home-dir "${APP_HOME}" --shell /usr/sbin/nologin app \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN bundle config set without "${BUNDLE_WITHOUT}" \
    && bundle install --jobs=4 --retry=3

COPY . .
RUN mkdir -p db log tmp \
    && chown -R app:app db log tmp

EXPOSE 9293

USER app:app

CMD ["bundle", "exec", "rackup", "--host", "0.0.0.0", "--port", "9293", "--option", "Threads=0:8"]

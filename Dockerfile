# Stage 1: build the mtncloud-cli gem from this repository.
# The gemspec lists its files with `git ls-files`, so this stage needs the .git
# directory in the build context. Only files tracked by git go into the gem.
FROM ruby:3.3 AS build
WORKDIR /src
COPY . .
RUN gem build mtncloud-cli.gemspec -o /mtncloud-cli.gem

# Stage 2: install the gem into a clean image.
# Only the built .gem is copied from stage 1, so nothing else from the build
# context (local files such as test_config.yaml, or the .git directory)
# ends up in the final image.
FROM ruby:3.3
COPY --from=build /mtncloud-cli.gem /tmp/mtncloud-cli.gem
RUN gem install /tmp/mtncloud-cli.gem --no-document \
 && rm /tmp/mtncloud-cli.gem

WORKDIR /root
ENTRYPOINT ["mtncloud"]

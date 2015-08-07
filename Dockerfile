FROM ruby:2.1.2

MAINTAINER Julie Silvestri julie@zearn.org

RUN apt-get update

ADD Gemfile /usr/src/app/
ADD Gemfile.lock /usr/src/app/
RUN bundle install --system

ENV PIVOTAL_TOKEN secret

RUN echo '{"https://index.docker.io/v1/":{"auth":"ZGthcGFkaWE6RTdvY0s4ZmFiOGh1ejZjaG9XOUF3YjZhWWN0","email":"dhruv@zearn.org"}}' > /.dockercfg

# When we run this image, we do something like this:
# docker run -v /var/run/docker.sock:/var/run/docker.sock -v /usr/bin/docker:/usr/bin/docker -d dkapadia/zearn-ci
# so that the container has a connection to the parent's docker daemon
CMD ["bundle", "exec", "rake", "pivotal::set_due_dates ALL=true"]

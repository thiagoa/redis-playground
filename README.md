# Redis Playground

This is supposed to be the main hub for anything I want to experiment in Redis.

## Requirements

A `redis-server` running on `localhost:6379`.

## Installing

```sh
$ bundle install
```

## Running the tests

```sh
bundle exec rake
```

## Voting system

The code in `voting.rb` is based on the first chapter of Redis in Action and
uses a procedural-oriented style. No transactions have been implemented yet.

### Buckets

- `article:article_id`: A `HASH` of article info: `title`, `time`, and `votes`.
- `voted:article_id`: A `SET` of voting users.
- `time`: A `ZSET` of `article_id => publish_date_timestamp`.
- `score`: A `ZSET` of `article_id => voting score`.
- `group:group_name`: A `ZSET` of article ids. One article can belong to many groups.

### Score calculation for a vote

- Timestamp in which the article was posted + constant multiplier * number of votes for the article.
- Constant: Seconds in a day (86.400) / number of votes required to last a full day (200) = 432.

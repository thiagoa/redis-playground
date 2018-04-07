ONE_WEEK_IN_SECONDS = 7 * 86_400
VOTE_SCORE = 432
KEY_GLOBS = ['article:*', 'voted:*', 'score:*', 'time:*', 'group:*']

def cleanup(conn)
  keys = KEY_GLOBS.flat_map { |k| conn.keys(k) }

  conn.multi do |multi|
    keys.each { |k| multi.del k }
  end
end

def post_article(conn, user, title, expires_in: ONE_WEEK_IN_SECONDS)
  article_id = conn.incr('article:')

  voted = "voted:#{article_id}"
  conn.sadd voted, user
  conn.expire voted, expires_in

  article = "article:#{article_id}"

  now = Time.now.to_i

  conn.hmset article,
    :title,  title,
    :poster, user,
    :time,   now,
    :votes,  1

  conn.zadd 'score:', now + VOTE_SCORE, article_id
  conn.zadd 'time:', now, article_id

  article_id
end

def time_posted(conn, article_id)
  time = conn.zscore('time:', article_id)
  time.to_i if time
end

def get_article(conn, article_id)
  article = conn.hgetall("article:#{article_id}")

  unless article.empty?
    article.merge('id' => article_id)
  end
end

def vote_article(conn, user, article_id)
  cutoff = Time.now.to_i - ONE_WEEK_IN_SECONDS
  publish_time = conn.zscore('time:', article_id) || 0
  return if cutoff > publish_time

  if conn.sadd("voted:#{article_id}", user)
    conn.zincrby 'score:', VOTE_SCORE, article_id
    conn.hincrby "article:#{article_id}", 'votes', 1
  end
end

def voted?(conn, user, article_id)
  conn.sismember("voted:#{article_id}", user)
end

def score_for(conn, article_id)
  conn.zscore('score:', article_id)
end

def get_articles(conn, page: 1, per_page: 10, order: 'score:')
  start = (page - 1) * per_page
  stop = start + per_page - 1

  article_ids = conn.zrevrange(order, start, stop)
  article_ids.map do |id|
    conn.hgetall("article:#{id}").merge('id' => id.to_i)
  end
end

def add_remove_groups(conn, article_id, to_add = [], to_rem = [])
  to_add.each { |name| conn.sadd("group:#{name}", article_id) }
  to_rem.each { |name| conn.srem("group:#{name}", article_id) }
end

def get_group_articles(conn, group, page: 1, per_page: 10, order: 'score:')
  key = order + group

  unless conn.exists(key)
    conn.zinterstore key, ["group:#{group}", order], aggregate: 'max'
    conn.expire key, 60
  end

  get_articles conn, page: page, per_page: per_page, order: key
end

require_relative 'test_helper'

class VotingTest < Minitest::Test
  VOTING_SCORE = 432
  CUTOFF_TIMESPAN = 86_400 * 7

  def now
    Time.now.to_i
  end

  def initial_score
    now + VOTING_SCORE
  end

  def setup
    Timecop.freeze
    @conn = Redis.new
  end

  def teardown
    Timecop.return
    cleanup(@conn)
  end

  def test_empty_article_returns_nil
    assert_nil get_article(@conn, 1)
    assert_nil time_posted(@conn, 1)
    assert_nil score_for(@conn, 1)
  end

  def test_post_one_article
    expected_article = {
      'id'     => 1,
      'title'  => 'Article 1',
      'poster' => 'user:2',
      'time'   => now.to_s,
      'votes'  => '1'
    }

    assert_equal 1, post_article(@conn, 'user:2', 'Article 1')
    assert_equal expected_article, get_article(@conn, 1)
    assert_equal initial_score, score_for(@conn, 1)
    assert_equal now, time_posted(@conn, 1)

    assert voted?(@conn, 'user:2', 1)
  end

  def test_post_two_articles
    expected_article_1 = {
      'id'     => 1,
      'title'  => 'Article 1',
      'poster' => 'user:1',
      'time'   => now.to_s,
      'votes'  => '1'
    }
    expected_article_2 = {
      'id'     => 2,
      'title'  => 'Article 2',
      'poster' => 'user:2',
      'time'   => now.to_s,
      'votes'  => '1'
    }

    assert_equal 1, post_article(@conn, 'user:1', 'Article 1')
    assert_equal expected_article_1, get_article(@conn, 1)
    assert_equal 2, post_article(@conn, 'user:2', 'Article 2')
    assert_equal expected_article_2, get_article(@conn, 2)

    assert voted?(@conn, 'user:1', 1)
    refute voted?(@conn, 'user:2', 1)
    assert voted?(@conn, 'user:2', 2)
    refute voted?(@conn, 'user:1', 2)
  end

  def test_vote_on_non_existing_article
    vote_article @conn, 'user:1', 1

    assert_nil score_for(@conn, 1)
  end

  def test_vote_on_existing_article
    article_id = post_article(@conn, 'user:2', 'Article 1')
    vote_article @conn, 'user:1', article_id

    score = score_for(@conn, article_id)
    article = get_article(@conn, article_id)

    assert_equal (initial_score + VOTING_SCORE), score
    assert_equal '2', article['votes']
    assert voted?(@conn, 'user:1', article_id)
  end

  def test_votes_on_cutoff
    article_id = post_article(@conn, 'user:2', 'Article 1')

    Timecop.freeze Time.now + CUTOFF_TIMESPAN do
      vote_article @conn, 'user:1', article_id

      assert voted?(@conn, 'user:1', article_id)
    end
  end

  def test_does_not_vote_after_cutoff
    article_id = post_article(@conn, 'user:2', 'Article 1')

    Timecop.freeze Time.now + CUTOFF_TIMESPAN + 1 do
      vote_article @conn, 'user:1', article_id

      refute voted?(@conn, 'user:1', article_id)
    end
  end

  def test_post_vote_expiration
    id = post_article(@conn, 'user:2', 'Article 1', expires_in: 1)

    sleep 1.05

    refute voted?(@conn, 'user:2', id)
  end

  def test_two_votes_on_existing_article
    article_id = post_article(@conn, 'user:2', 'Article 1')

    vote_article @conn, 'user:1', article_id
    vote_article @conn, 'user:3', article_id

    score = score_for(@conn, article_id)
    article = get_article(@conn, article_id)

    assert_equal (initial_score + (VOTING_SCORE * 2)), score
    assert_equal '3', article['votes']
    assert voted?(@conn, 'user:1', article_id)
    assert voted?(@conn, 'user:3', article_id)
  end

  def test_vote_on_existing_article_by_same_user
    article_id = post_article(@conn, 'user:2', 'Article 1')

    2.times do
      vote_article @conn, 'user:1', article_id
    end

    score = score_for(@conn, article_id)
    article = get_article(@conn, article_id)

    assert_equal (initial_score + VOTING_SCORE), score
    assert_equal '2', article['votes']
    assert voted?(@conn, 'user:1', article_id)
  end

  def test_get_articles_with_no_votes_orders_by_most_recent_desc
    post_article(@conn, 'user:1', 'Article 1')
    post_article(@conn, 'user:2', 'Article 2')

    expected_article_2 = {
      'id'     => 2,
      'title'  => 'Article 2',
      'poster' => 'user:2',
      'time'   => now.to_s,
      'votes'  => '1'
    }
    expected_article_1 = {
      'id'     => 1,
      'title'  => 'Article 1',
      'poster' => 'user:1',
      'time'   => now.to_s,
      'votes'  => '1'
    }

    articles = get_articles(@conn)

    assert_equal 2, articles.size
    assert_equal expected_article_2, articles[0]
    assert_equal expected_article_1, articles[1]
  end

  def fetch_article_ids(*args, **kwargs)
    get_articles(@conn, *args, **kwargs).map { |a| a['id'] }
  end

  def fetch_group_article_ids(*args, **kwargs)
    get_group_articles(@conn, *args, **kwargs).map { |a| a['id'] }
  end

  def test_get_articles_gets_10_articles_by_default
    expected_article_ids = (1..11).map do |n|
      post_article(@conn, "user:#{n}", "Article #{n}")
    end
    expected_article_ids.shift

    assert_equal expected_article_ids.sort, fetch_article_ids.sort
  end

  def test_get_articles_paginates_correctly
    id_1 = post_article(@conn, 'user:1', 'Article 1')
    id_2 = post_article(@conn, 'user:1', 'Article 2')
    id_3 = post_article(@conn, 'user:1', 'Article 2')
    id_4 = post_article(@conn, 'user:1', 'Article 2')

    assert_equal [id_4, id_3], fetch_article_ids(page: 1, per_page: 2)
    assert_equal [id_2, id_1], fetch_article_ids(page: 2, per_page: 2)
  end

  def test_get_articles_with_votes_orders_by_highest_score_desc
    id_1 = post_article(@conn, 'user:1', 'Article 1')
    id_2 = post_article(@conn, 'user:2', 'Article 2')
    id_3 = post_article(@conn, 'user:3', 'Article 3')

    vote_article(@conn, 'user:3', id_1)
    vote_article(@conn, 'user:3', id_2)
    vote_article(@conn, 'user:4', id_2)

    assert_equal [id_2, id_1, id_3], fetch_article_ids
  end

  def test_adds_an_article_to_a_group
    id_1  = post_article(@conn, 'user:1', 'Article 1')
    _id_2 = post_article(@conn, 'user:2', 'Article 2')

    add_remove_groups @conn, id_1, ['Programming']

    group_articles = fetch_group_article_ids('Programming')

    assert_equal group_articles, [id_1]
  end

  def test_adds_articles_to_multiple_groups
    id_1  = post_article(@conn, 'user:1', 'Article 1')
    id_2  = post_article(@conn, 'user:2', 'Article 2')
    _id_3 = post_article(@conn, 'user:3', 'Article 3')

    add_remove_groups @conn, id_1, ['Programming', 'Magic']
    add_remove_groups @conn, id_2, ['Gardening', 'Magic']

    group_articles = fetch_group_article_ids('Programming')
    assert_equal group_articles, [id_1]

    group_articles = fetch_group_article_ids('Magic')
    assert_equal group_articles, [id_2, id_1]

    group_articles = fetch_group_article_ids('Gardening')
    assert_equal group_articles, [id_2]
  end

  def test_removes_article_from_one_group
    id_1  = post_article(@conn, 'user:1', 'Article 1')

    add_remove_groups @conn, id_1, ['Programming']
    add_remove_groups @conn, id_1, [], ['Programming']

    group_articles = fetch_group_article_ids('Programming')
    assert_equal group_articles, []
  end

  def test_add_remove_from_group
    id_1 = post_article(@conn, 'user:1', 'Article 1')

    add_remove_groups @conn, id_1, ['Programming', 'Magic', 'Other']
    add_remove_groups @conn, id_1, [], ['Programming', 'Other']

    group_articles = fetch_group_article_ids('Programming')
    assert_equal group_articles, []

    group_articles = fetch_group_article_ids('Magic')
    assert_equal group_articles, [id_1]

    group_articles = fetch_group_article_ids('Other')
    assert_equal group_articles, []
  end
end

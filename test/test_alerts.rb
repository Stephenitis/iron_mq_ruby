# Put config.yml file in ~/Dropbox/configs/ironmq_gem/test/config.yml
require File.expand_path('test_base.rb', File.dirname(__FILE__))
require 'logger'

class TestAlerts < TestBase

  def setup
    super
    @skip = @host.include? 'rackspace'
    return if @skip # bypass these tests if rackspace
  end

  def test_size_alerts
    return if @skip

    type = 'size'
    trigger = 10
    # Test size alets, direction is ascending
    queue, alert_queue = clear_queue_add_alert(type, trigger, 'asc')

    # queue size will be trigger + 3
    trigger_alert(queue, alert_queue, trigger, 3)

    # must not trigger alert, queue size will be trigger + 13
    post_messages(queue, 10)
    assert_equal 1, get_queue_size(alert_queue)

    # must not trigger alert, queue size will be trigger - 3
    delete_messages(queue, 16)
    assert_equal 1, get_queue_size(alert_queue)

    trigger_alert(queue, alert_queue, trigger)

    delete_queues(queue, alert_queue)

    # Test size alerts, direction is descending
    queue, alert_queue = clear_queue_add_alert(type, trigger, 'desc')

    # must not trigger descending alert
    post_messages(queue, 15)
    assert_equal 0, get_queue_size(alert_queue)

    # will remove 5 msgs, queue size will be 10
    trigger_alert(queue, alert_queue, trigger)

    # must not trigger alert
    post_messages(queue, 12)
    assert_equal 1, get_queue_size(alert_queue)

    trigger_alert(queue, alert_queue, trigger)

    # must not trigger alert
    delete_messages(queue, 8)
    assert_equal 2, get_queue_size(alert_queue)

    delete_queues(queue, alert_queue)

    # Test size alerts, direction is "both"
    queue, alert_queue = clear_queue_add_alert(type, trigger, 'both')

    # trigger ascending alert
    trigger_alert(queue, alert_queue, trigger)

    # must not trigger alert
    post_messages(queue, 8)
    assert_equal 1, get_queue_size(alert_queue)

    # trigger descending alert, queue size will be trigger - 3
    trigger_alert(queue, alert_queue, trigger, 3)

    # trigger ascending alert, queue size will be trigger + 3
    trigger_alert(queue, alert_queue, trigger, 3)

    delete_queues(queue, alert_queue)
  end

  def test_progressive_alerts
    return if @skip

    type = 'progressive'
    trigger = 10
    # Test ascending progressive alert
    queue, alert_queue = clear_queue_add_alert(type, trigger, 'asc')

    # Trigger 3 alerts
    (1..3).each { |n| trigger_alert(queue, alert_queue, n * trigger) }

    # Must not trigger alerts
    delete_messages(queue, 15)
    assert_equal 3, get_queue_size(alert_queue)

    trig = (get_queue_size(queue) / trigger.to_f).ceil * trigger
    trigger_alert(queue, alert_queue, trig)

    # must not trigger alert
    delete_messages(queue, get_queue_size(queue) - 1)

    delete_queues(queue, alert_queue)

    # Test descending progressive alert
    queue, alert_queue = clear_queue_add_alert(type, trigger, 'desc')

    # must not trigger alert
    post_messages(queue, 25)
    assert_equal 0, get_queue_size(alert_queue)

    # trigger descending alert twice
    2.downto(1) { |n| trigger_alert(queue, alert_queue, n * trigger) }

    # must not trigger alert at size of 0
    delete_messages(queue, 5)
    assert_equal 2, get_queue_size(alert_queue)

    # must not trigger alert
    post_messages(queue, 15)
    assert_equal 2, get_queue_size(alert_queue)

    delete_queues(queue, alert_queue)

    # Test "both" direction progressive alerts
    queue, alert_queue = clear_queue_add_alert(type, trigger, 'both')

    trigger_alert(queue, alert_queue, trigger, 2)
    trigger_alert(queue, alert_queue, 2 * trigger) # queue size = 2 * trigger

    # must not trigger descending alert
    delete_messages(queue, trigger / 2)
    assert_equal 2, get_queue_size(alert_queue)

    # trigger descending alert, queue size will be trigger - 3
    trigger_alert(queue, alert_queue, trigger, 3)

    # trigger ascending alert, queue size will be trigger + 5
    trigger_alert(queue, alert_queue, trigger, 5)

    # must not trigger alerts below, queue size will be 2 * trigger - 1
    post_messages(queue, trigger - 5 - 1)
    assert_equal 4, get_queue_size(alert_queue)

    # one message before trigger value
    delete_messages(queue, trigger - 2)
    assert_equal 4, get_queue_size(alert_queue)

    delete_queues(queue, alert_queue)
  end

  def post_messages(queue, n)
    queue.post(Array.new(n, { :body => 'message' }))
    sleep 1
  end

  def delete_messages(queue, n)
    msgs = queue.get(:n => n)
    [msgs].flatten.each { |msg| msg.delete }
    sleep 1
  end

  def delete_queues(*queues)
    queues.each { |q| q.delete_queue }
  end

  def trigger_alert(queue, alert_queue, trigger, overhead = 0)
    puts "trigger_alert(), called at #{caller[0]}"

    qsize = get_queue_size(queue)
    puts "Initial queue size is #{qsize}"
    puts 'Alert is already triggered!' if qsize == trigger
    aq_size = get_queue_size(alert_queue)

    if qsize < trigger
      nmsgs = trigger - qsize - 1
      puts "Try to trigger ascending alert... post #{nmsgs} messages"
      post_messages(queue, nmsgs)
    else
      nmsgs = qsize - trigger - 1
      puts "Try to trigger descending alert... delete #{nmsgs} messages"
      delete_messages(queue, nmsgs)
    end
    assert_equal aq_size, get_queue_size(alert_queue)

    if qsize < trigger
      puts "Post more #{1 + overhead} messages"
      post_messages(queue, 1 + overhead)
    else
      puts "Delete more #{1 + overhead} messages"
      delete_messages(queue, 1 + overhead)
    end
    assert_equal aq_size + 1, get_queue_size(alert_queue)
  end

  def clear_queue_add_alert(type, trigger, direction)
    puts "clear_queue_add_alert(), called at #{caller[0]}"

    qname = "#{type}-#{direction}-#{trigger}"
    alert_qname = "#{qname}-alerts"

    queue = @client.queue(qname)
    alert_queue = @client.queue(alert_qname)
    # delete instead of clearing to remove all alerts from queue
    delete_queues(queue, alert_queue)
    # todo: should :queue be called something else,
    # like alert_queue? or url and have to use ironmq:// url?
    r = queue.add_alert({ :type => type, :trigger => trigger,
                          :queue => alert_qname, :direction => direction })
    #p r

    alerts = queue.alerts
    #p alerts

    assert_equal 1, alerts.size
    alert = alerts[0]
    #p alert
    assert_equal type, alert.type
    assert_equal trigger, alert.trigger
    assert_equal alert_qname, alert.queue
    assert_equal direction, alert.direction

    [queue, @client.queue(alert_qname)]
  end

  def get_queue_size(queue)
    begin
      queue.reload.size
    rescue Rest::HttpError => ex
      ex.message =~ /404/ ? 0 : raise(ex)
    end
  end

end

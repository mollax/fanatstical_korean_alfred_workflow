# encoding: utf-8
require 'date'
require 'cgi'
require 'uri'

begin
    require 'iconv'
rescue LoadError
end

def debug(msg)
    File.open File.expand_path('~')+'/.alfred.debug.log.txt', 'a' do |file|
        file.write msg
        file.write "\n"
    end
end

unless "".respond_to? :ord
    class String
        def ord
            self[0]
        end
    end
end

def nfd(str)
    converted = ''
    str.split('').each do |c|
        if c.ord >= 0xAC00 and c.ord <= 0xD7A3
            r = []
            a = (c.ord - 0xAC00)
            r << 0x1100 + ((a-a%28)/28)/21
            r << 0x1161 + ((a-a%28)/28)%21
            r << 0x11A8 + (a%28-1) if a%28 > 0
            converted += r.map{|e|[e].pack('U')}.join
        else
            converted += c
        end
    end
    return converted
end

def nfc(str)
    converted = ''
    str = str.split('')

    i = 0
    while i < str.length
        if str[i].ord >= 0x1100 and str[i].ord <= 0x11FF
            j = i
            chr = []
            while str[j].ord >= 0x1100 and str[j].ord <= 0x11FF
                break unless (str[j].ord >= 0x1100 and str[j].ord <= 0x11FF)

                chr << str[j].ord
                break if str[j+1].nil? or str[j+1].ord < 0x1100 or str[j+1].ord > 0x11FF or (str[j+1].ord >= 0x1100 and str[j+1].ord <= 0x115F)
                j += 1
                i += 1
            end
            built = 0xAC00
            chr.each_with_index do |c, i|
                case i
                when 0
                    built += (c-0x1100)*588
                when 1
                    built += (c-0x1161)*28
                when 2
                    built += c-0x11A8+1
                end
            end
            converted += [built].pack('U')
        else
            converted += str[i]
        end

        i += 1
    end
    return converted
end

exit if ARGV.empty?

if defined? Iconv
    schedule_string = Iconv.new('UTF-8', 'UTF-8-MAC').iconv(ARGV.join(' '))
elsif String.method_defined? :encode
    schedule_string = ARGV.join(' ').encode('UTF-8', 'UTF-8-MAC')
else
    schedule_string = ARGV.join(' ')
end

schedule_string = nfc(schedule_string)

now = Date.today
matcher = /^((이달|이번달|담달|다음달|(내년|[0-9]{4}년){0,1} *[0-9]+월){0,1} *[0-9]+일+|오늘|내일|모레|(이번주|담주|다음주|다담주|다다음주){0,1} *([월화수목금토일](요일|욜)))( *(새벽|아침|점심|오전|오후|저녁|밤){0,1} *([0-9]+시|[0-9]+:[0-9]+) *([0-9]+분|반){0,1}){0,1}에{0,1}( *(.+)에서){0,1} */u

sentence = schedule_string
if schedule_string =~ matcher
    absolute_date, week_modifier, weekday = $1, $4, $5
    ampm, hour, minute = $8, $9, $10||0
    place = $12

    if absolute_date
        day_modifier = %w(오늘 내일 모레).index absolute_date if absolute_date =~ /(오늘|내일|모레)/u
        if absolute_date =~ /(이달|이번달|담달|다음달)/u
            month_modifier = 0 if absolute_date and absolute_date =~ /(이달|이번달)/u
            month_modifier = 1 if absolute_date and absolute_date =~ /(담달|다음달)/u
            day = $1.to_i if absolute_date =~ /([0-9]+)일/u
        end
        if absolute_date =~ /(내년|([0-9]{4})년) *([0-9]+)월 *([0-9]+)일/u
            year = now.year + 1 if absolute_date.index '내년'
            year = $2.to_i if $2
            month = $3.to_i if $3
            day = $4.to_i if $4
        end
    end
    absolute_date = absolute_date =~ /^[0-9월일 ]+$/u ? absolute_date.strip : nil

    week_modifier = 0 if %w(이번주).include? week_modifier
    week_modifier = 7 if %w(담주 다음주).include? week_modifier
    week_modifier = 14 if %w(다담주 다다음주).include? week_modifier

    weekday = %w(일 월 화 수 목 금 토).index weekday.gsub(/^([월화수목금토일]).*/u, '\1') if weekday

    if hour
        if hour =~ /^([0-9]+):([0-9]+)$/u
            hour = $1.to_i
            minute = $2 + "분"
        else
            hour = hour.gsub(/[^0-9]/, '').to_i if hour
        end
    end

    ampm = :am if ampm.is_a? String and %w(새벽 아침 오전).include? ampm
    ampm = :pm if ampm.is_a? String and %w(점심 오후 저녁 밤).include? ampm
    minute = minute == '반' ? 30 : minute.gsub(/분/, '').to_i if minute.is_a? String

    if absolute_date and absolute_date =~ /(([0-9]+)월){0,1} *([0-9]+)일/u
        year = now.year.to_i
        month = ($2 || now.month).to_i
        day = $3.to_i
    elsif month_modifier and day
        date = now >> month_modifier
        date = date - date.day + day
    elsif weekday
        weekday = 7 if weekday == 0
        if week_modifier
            date = now + week_modifier - now.wday + weekday
        else
            date = now - now.wday + weekday
        end
    elsif day_modifier
        date = now + day_modifier
    end

    year = date.year if date
    month = date.month if date
    day = date.day if date

    if hour
        hour += 12 if ampm == :pm and hour <= 12
    else
        minute = nil
    end

    subject = schedule_string.gsub(matcher, '')

    if hour and minute
        time = Time.local(year, month, day, hour, minute)
        now = Time.now
    else
        time = Time.local(year, month, day)
        now = Time.local(now.year, now.month, now.day)
    end

    if time < now
        time += 60*60*24*7
        year, month, day = time.year, time.month, time.day
    end

    if month and day
        sentence = "#{subject} %02d.%02d.%02d" % [month, day, year]
        sentence += " at %02d:%02d" % [hour, minute] if hour and minute
    end

    if place
        sentence += " @ #{place} "
    end
end
outSentence = URI.encode("x-fantastical2://parse?s=#{sentence}")
system("open", outSentence)

puts outSentence

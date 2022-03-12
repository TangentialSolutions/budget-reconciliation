#!/Users/trevorbroaddus/.rvm/rubies/ruby-2.6.3/bin/ruby

# @notes
#
# Reconciliation does a rough guess at which transactions are missing from USAA, and which are missing from Everydollar.
# The following are not considered when reporting missing transactions:
#
# - Split charges in Everydollar
#   - these are exported as separate charges in the .csv
#   - in the future, the `download.rb` script will scrape the webpage instead of using the default CSV download link
# - Transfers in USAA and Everydollar
#   - both platforms allow transferring money between accounts (or line-items in ED speak)

require "csv"

class Reconcile
  Transaction = Struct.new(:type, :merchant, :amount)

  # ed_transactions: {
  #   AMOUNT_STRING => Transaction
  # }
  # usaa_transactions: {
  #   AMOUNT_STRING => Transaction
  # }
  # result_map:
  # {
  #       missing_in_ed: { AMOUNT_STRING => Transaction },
  #       missing_in_usaa: { AMOUNT_STRING => Transaction }
  #     }
  attr_accessor :ed_transactions, :usaa_transactions, :result_map

  def perform
    load_ed_transactions
    load_usaa_transactions
    reconcile
    output
  end

  def reconcile
    raise StandardError.new("No EveryDollar transactions to reconcile") if ed_transactions.empty?
    raise StandardError.new("No USAA transactions to reconcile") if usaa_transactions.empty?

    ed_transactions.each do |amount, transaction|
      if usaa_transactions.keys.include?(amount) == false
        missing_in_usaa(transaction)
      end
    end

    usaa_transactions.each do |amount, transaction|
      if ed_transactions.keys.include?(amount) == false
        missing_in_ed(transaction)
      end
    end
  end

  def output
    puts "Missing in EveryDollar:"
    result_map[:missing_in_ed].each do |amount, transaction|
      puts "#{amount} - #{transaction.merchant}"
    end

    puts "Missing in USAA:"
    result_map[:missing_in_usaa].each do |amount, transaction|
      puts "#{amount} - #{transaction.merchant}"
    end
  end

  def result_map
    @result_map ||= {
      missing_in_ed: {},
      missing_in_usaa: {}
    }
  end

  def ed_transactions
    @ed_transactions ||= {}
  end

  def usaa_transactions
    @usaa_transactions ||= {}
  end

  def add_ed_transaction(transaction)
    ed_transactions[transaction.amount] = transaction
  end

  def add_usaa_transaction(transaction)
    usaa_transactions[transaction.amount] = transaction
  end

  def missing_in_ed(transaction)
    raise StandardError unless transaction.is_a?(Transaction)

    result_map[:missing_in_ed][transaction.amount] = transaction
  end

  def missing_in_usaa(transaction)
    raise StandardError unless transaction.is_a?(Transaction)

    result_map[:missing_in_usaa][transaction.amount] = transaction
  end

  def load_usaa_transactions
    filepath = "/Users/trevorbroaddus/Documents/Projects/budget-reconciliation/budgets/03-2022-00-Usaa-Transactions.csv"
    CSV.foreach(filepath, headers: true) do |row|
      row = row.to_hash
      amount = row["Amount"]
      type = amount["-"].nil? ? :deposit : :debit

      add_usaa_transaction(Transaction.new(type, row["Merchant"], amount))
    end
  end

  def load_ed_transactions
    filepath = "/Users/trevorbroaddus/Documents/Projects/budget-reconciliation/budgets/03-2022-EveryDollar-Transactions.csv"
    CSV.foreach(filepath, headers: true, encoding: "bom|utf-8") do |row|
      row = row.to_hash
      amount = row["Amount"]
      type = amount["-"].nil? ? :deposit : :debit

      add_ed_transaction(Transaction.new(type, row["Merchant"], amount))
    end
  end
end

Reconcile.new.perform
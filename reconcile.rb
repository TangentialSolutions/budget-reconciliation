class Reconcile
  def perform

    {
      missing_in_ed: [
        {
          type: "",
          merchant: "",
          amount: ""
        }
      ],
      missing_in_usaa: []
    }
  end

  def load_usaa_transactions
    filepath = "/Users/trevorbroaddus/Documents/Projects/budget-reconciliation/budgets/09-2021-Usaa-Transactions.csv"
    CSV.foreach(filepath, headers: true) do |row|
      
    end
  end

  def load_ed_transactions
    filepath = "/Users/trevorbroaddus/Documents/Projects/budget-reconciliation/budgets/09-2021-EveryDollar-Transactions.csv"
  end
end
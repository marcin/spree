require 'spree_core'
require 'spree_promotions_hooks'

module SpreePromotions
  class Engine < Rails::Engine
    def self.activate
      # put class_eval and other logic that depends on classes outside of the engine inside this block
      Product.class_eval do
        has_and_belongs_to_many :promotion_rules

        def possible_promotions
          rules_with_matching_product_groups = product_groups.map(&:promotion_rules).flatten
          all_rules = promotion_rules + rules_with_matching_product_groups
          promotion_ids = all_rules.map(&:promotion_id).uniq
          Promotion.automatic.scoped(:conditions => {:id => promotion_ids})
        end
      end

      ProductGroup.class_eval do
        has_many :promotion_rules
      end

      Order.class_eval do
        #has_many :promotion_credits, :extend => Order::Totaling, :order => :position
        def products
          line_items.map {|li| li.variant.product}
        end

        # def update_totals(force_adjustment_recalculation=false)
        #   self.item_total       = self.line_items.total
        #
        #   # save the items which might be changed by an order update, so that
        #   # charges can be recalculated accurately.
        #   self.line_items.map(&:save)
        #
        #   process_automatic_promotions
        #
        #   if !self.checkout_complete || force_adjustment_recalculation
        #     applicable_adjustments, adjustments_to_destroy = adjustments.partition{|a| a.applicable?}
        #     self.adjustments = applicable_adjustments
        #     adjustments_to_destroy.each(&:destroy)
        #   end
        #
        #   self.adjustment_total = self.charge_total - self.credit_total
        #   self.total            = self.item_total   + self.adjustment_total
        #
        #   self.checkout.enable_validation_group(:register) unless self.checkout.nil?
        # end


        def process_automatic_promotions
          #promotion_credits.reload.clear
          eligible_automatic_promotions.each do |coupon|
            # can't use coupon.create_discount as it re-saves the order causing an infinite loop
            if amount = coupon.calculator.compute(line_items)
              amount = item_total if amount > item_total
              promotion_credits.reload.clear unless coupon.combine? and promotion_credits.all? { |credit| credit.adjustment_source.combine? }
              promotion_credits.create!({
                  :adjustment_source => coupon,
                  :amount => amount,
                  :description => coupon.description
                })
            end
          end.compact
        end

        def eligible_automatic_promotions
          @eligible_automatic_coupons ||= Promotion.automatic.select{|c| c.eligible?(self)}
        end
      end

      # if File.basename( $0 ) != "rake"
      #   # register promotion rules
      #   [Promotion::Rules::ItemTotal, Promotion::Rules::Product, Promotion::Rules::User, Promotion::Rules::FirstOrder].each &:register
      #
      #   # register default promotion calculators
      #   [
      #     Calculator::FlatPercentItemTotal,
      #     Calculator::FlatRate,
      #     Calculator::FlexiRate,
      #     Calculator::PerItem,
      #     Calculator::FreeShipping
      #   ].each{|c_model|
      #     begin
      #       Promotion.register_calculator(c_model) if c_model.table_exists?
      #     rescue Exception => e
      #       $stderr.puts "Error registering promotion calculator #{c_model}"
      #     end
      #   }
      # end
    end

    config.autoload_paths += %W(#{config.root}/lib)
    config.to_prepare &method(:activate).to_proc
  end
end

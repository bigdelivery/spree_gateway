module Spree
  class Gateway::Maxipago < Gateway
    preference :login, :string # ID
    preference :password, :string # KEY
    
    def provider_class
      ActiveMerchant::Billing::MaxipagoGateway
    end

    def payment_profiles_supported?
      true
    end

    def create_profile(payment)
      return unless payment.source.gateway_customer_profile_id.nil?
      options = {
        customer_id: payment.source.gateway_customer_profile_id
      }.merge! address_for(payment)

      # Create payment
      return if source.number.blank? || source.gateway_payment_profile_id.present?

      creditcard = source
      response = provider.store(creditcard, options)
      if response.success?
        payment.source.update_attributes!({
          gateway_payment_profile_id: response.params["token"]
        })
      else
        payment.send(:gateway_error, response.message)
      end
    end

    def options_for_purchase_or_auth(money, creditcard, gateway_options)
      options = {}
      options[:description] = "Spree Order ID: #{gateway_options[:order_id]}"

      if creditcard.gateway_customer_profile_id && creditcard.gateway_payment_profile_id
        creditcard = provider_class::MaxipagoPaymentToken.new({
          customer_id: credit_card.gateway_customer_profile_id,
          token: credit_card.gateway_payment_profile_id
        })
      end
      return money, creditcard, options
    end

    def address_for(payment)
      {}.tap do |options|
        if address = payment.order.bill_address
          options.merge!(address: {
            address1: address.address1,
            address2: address.address2,
            city: address.city,
            zip: address.zipcode
          })

          if country = address.country
            options[:address].merge!(country: country.name)
          end

          if state = address.state
            options[:address].merge!(state: state.name)
          end
        end
      end
    end
    

    def auto_capture?
      true
    end
  end
end

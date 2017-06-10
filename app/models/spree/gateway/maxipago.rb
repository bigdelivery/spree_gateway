module Spree
  class Gateway::Maxipago < Gateway
    preference :login, :string # ID
    preference :password, :string # KEY
    
    def provider_class
      ActiveMerchant::Billing::MaxipagoGateway
    end

    def purchase(money, creditcard, gateway_options)
      provider.purchase(*options_for_purchase_or_auth(money, creditcard, gateway_options))
    end

    def authorize(money, creditcard, gateway_options)
      provider.purchase(*options_for_purchase_or_auth(money, creditcard, gateway_options))
    end

    def payment_profiles_supported?
      true
    end

    def create_profile(payment)
      return unless payment.source.gateway_payment_profile_id.nil?
      source = payment.source

      # Try to 
      if source.gateway_customer_profile_id.nil?
        if source.respond_to?(:user) && source.user
          source_with_possible_customer_id = source.class.where(user_id: source.user.id).find do |source|
            source.gateway_customer_profile_id.present?
          end
          if source_with_possible_customer_id.present?
            possible_customer_id = source_with_possible_customer_id.gateway_customer_profile_id
          else
            user_info = {
              customerIdExt: source.user.id,
              firstName: source.user.first_name,
              lastName: source.user.last_name,
              zip: payment.order.bill_address.zipcode,
              email: source.user.email,
              dob: "04/23/1997",
              ssn: source.user.cpf,
              sex: "M"
            }.delete_if{ |_k, v| v.nil? || v == "" }
            response = provider.add_customer(user_info)
            possible_customer_id = response.params["customer_id"]
          end
        end
      end
      customer_id = source.gateway_customer_profile_id || possible_customer_id

      # Build options hash
      options = if customer_id
        { customer_id: customer_id }
      else
        {}
      end
      options.merge! address_for(payment)

      source = payment.source
      user = payment.order.user
      
      # Create payment
      return if source.number.blank?

      creditcard = source
      response = provider.store(creditcard, options)
      if response.success?
        payment.source.update_attributes!({
          gateway_payment_profile_id: response.params["token"],
          gateway_customer_profile_id: customer_id,
        })
      else
        provider.delete_customer(possible_customer_id)
        payment.send(:gateway_error, response.message)
      end
    end

    def options_for_purchase_or_auth(money, creditcard, gateway_options)
      options = {}
      options[:description] = "Spree Order ID: #{gateway_options[:order_id]}"

      if creditcard.gateway_customer_profile_id && creditcard.gateway_payment_profile_id
        creditcard = provider_class::MaxipagoPaymentToken.new({
          customer_id: creditcard.gateway_customer_profile_id,
          token: creditcard.gateway_payment_profile_id
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

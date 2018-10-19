module Spree
  class Gateway::Maxipago < Gateway
    preference :login, :string # ID
    preference :password, :string # KEY
    preference :processor_id, :string

    def provider_class
      ActiveMerchant::Billing::MaxipagoGateway
    end

    def purchase(money, creditcard, gateway_options)
      provider.authorize(*options_for_purchase_or_auth(money, creditcard, gateway_options))
    end

    def authorize(money, creditcard, gateway_options)
      provider.authorize(*options_for_purchase_or_auth(money, creditcard, gateway_options))
    end

    def payment_profiles_supported?
      true
    end

    def create_profile(payment)
      return unless payment.source.gateway_payment_profile_id.nil? && payment.source.gateway_customer_profile_id.nil?
      
      source = payment.source
      # Try to create a customer_id from the information provided
      user_info = {
        customerIdExt: SecureRandom.uuid,
        firstName: source.user.first_name,
        lastName: source.user.last_name,
        zip: payment.order.bill_address.zipcode,
        email: source.user.email,
        dob: "04/23/1997",
        ssn: source.user.cpf,
        sex: "M"
      }.delete_if{ |_k, v| v.nil? || v == "" }
      response = provider.add_customer(user_info)
      return unless response.success?

      # Create options hash with customer_id
      customer_id = response.params["customer_id"]
      options = {
        customer_id: customer_id
      }
      options.merge! address_for(payment)
      # Create payment
      return if source.number.blank?
      creditcard = source
      response = provider.store(creditcard, options)
      cc_type = payment.source.to_active_merchant.brand

      if response.success?
        payment.source.update_attributes!({
          cc_type: cc_type,
          gateway_payment_profile_id: response.params["token"],
          gateway_customer_profile_id: customer_id,
        })
      else
        provider.delete_customer(customer_id)
        puts "RESPONSE: #{response.error_code} and #{response.message}"
        puts response
        payment.send(:gateway_error, response.error_code || response.message)
      end
    end

    def options_for_purchase_or_auth(money, creditcard, gateway_options)
      options = {}
      options[:description] = "Spree Order ID: #{gateway_options[:order_id]}"
      options[:order_id] = gateway_options[:order_id]
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

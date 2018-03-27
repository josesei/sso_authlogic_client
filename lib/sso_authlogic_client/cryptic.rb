module SsoAuthlogicClient::Cryptic
  def self.obscure(value, key)
    Base64::encode64(crypt(:encrypt, key, value))
  end

  def self.unobscure(value, key)
    return value if !value
    crypt(:decrypt, key, Base64::decode64(value)).force_encoding('UTF-8')
  end

  def self.crypt(method, key, value)
    return value unless value && value.length > 0
    cipher = OpenSSL::Cipher::Cipher.new("aes-256-cbc")
    cipher.send(method)
    cipher.pkcs5_keyivgen(key)
    cipher.update(value) + cipher.final
  end
end

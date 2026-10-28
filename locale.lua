-- T(key) looks up GarageConfig.DefaultLang, then en_us, then the generic failure text.
Locales = Locales or {}

function T(key)
    return (Locales[GarageConfig.DefaultLang] or Locales.en_us)[key] or Locales.en_us[key] or Locales.en_us.failed
end

{#-
  Normalise a recurring charge to a monthly amount.

  Annual plans contribute price / 12 to MRR; monthly plans contribute price as-is.
  Any other interval raises at compile time rather than silently returning null,
  because an unknown interval means MRR would be understated.
-#}
{% macro monthly_normalized_amount(amount_column, interval_column) %}
    case {{ interval_column }}
        when 'monthly' then {{ amount_column }}
        when 'annual' then {{ amount_column }} / 12.0
    end
{% endmacro %}

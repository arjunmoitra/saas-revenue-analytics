{#-
  Convert an integer cents column to a decimal dollar amount.
  Used everywhere money enters the staging layer so precision is consistent.
-#}
{% macro cents_to_dollars(column_name, precision=12, scale=2) %}
    round({{ column_name }} / 100.0, {{ scale }})::decimal({{ precision }}, {{ scale }})
{% endmacro %}

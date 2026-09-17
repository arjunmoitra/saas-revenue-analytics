{#-
  Generic test: fail if any row has a negative value in the column.
  Used for MRR, ARR, seats and other measures that can never be below zero.
-#}
{% test non_negative(model, column_name) %}

select {{ column_name }} as negative_value
from {{ model }}
where {{ column_name }} < 0

{% endtest %}

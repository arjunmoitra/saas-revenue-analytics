{#-
  Use the schema configured on the model (staging / intermediate / marts)
  directly instead of dbt's default "<target_schema>_<custom_schema>" prefixing,
  so the warehouse reads as raw -> staging -> intermediate -> marts.
-#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}

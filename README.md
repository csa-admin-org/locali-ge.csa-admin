# locali-ge.csa-admin.org

A small Sinatra app to handle locali-ge.ch WooCommerce webhooks and automatically create a new member in the CSA Admin organization.

The mapping of the WooCommerce products to the CSA Admin organization resources is handled in the `config/mapping.yml` file. The `api_endpoint` of the CSA Admin API must be set in the `config/config.yml` file for each organization.

## Deployment

The `WEBHOOK_SECRET` environment variable must be set to the WooCommerce webhook secret.

For each organization, the `<ORGANIZATION>_API_TOKEN` environment variable must be set.

## Testing

```sh
bundle install
bundle exec ruby test/*_test.rb
```

## Author

[Thibaud Guillaume-Gentil](https://thibaud.gg)

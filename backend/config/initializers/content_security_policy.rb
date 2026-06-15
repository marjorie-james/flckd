# Strict, self-origin-only Content Security Policy (anonymity: FR-012a). All
# scripts, styles, fonts, images, and connections must be same-origin so the
# browser never reaches a third party while planning a route. The only outbound
# navigation is the user-initiated maps handoff (a top-level link the user
# explicitly clicks), which CSP's default-src does not block.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src     :self
    policy.img_src      :self, :data, :blob
    policy.object_src   :none
    policy.script_src   :self
    policy.style_src    :self, :unsafe_inline # MapLibre injects inline styles
    policy.connect_src  :self
    policy.worker_src   :self, :blob          # MapLibre uses web workers
    policy.base_uri     :self
    policy.form_action  :self
    policy.frame_ancestors :none
  end

  # Send the policy enforced (not report-only).
  config.content_security_policy_report_only = false
end

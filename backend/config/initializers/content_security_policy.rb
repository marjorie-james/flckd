# Strict, self-origin-only Content Security Policy (anonymity: FR-012a). All
# scripts, styles, fonts, images, and connections must be same-origin so the
# browser never reaches a third party while planning a route. There is no
# outbound third-party navigation. The only way a route leaves the app is a
# user-initiated, fully client-side GPX file export built in the browser
# (RouteExport.tsx) — nothing is transmitted, so no CSP egress allowance is
# needed.
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

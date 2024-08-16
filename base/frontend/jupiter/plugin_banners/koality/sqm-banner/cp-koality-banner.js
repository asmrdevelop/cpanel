const path = `../plugin_banners/koality/sqm-banner/`;
const reset = "style-resets.css";
const styles = "banner-styles.css";
const template = document.createElement("template");
// I included <style> tags in the markup here to hide the component before it
// displayed on the page. From an external stylesheet (e.g. <link>), the text
// from the component would be temporarily visible before the css was applied
// to it.
template.innerHTML = `
  <style>
    :host {
      display: none;
    }
  </style>

  <link rel="stylesheet" href="${path}${reset}"/>
  <link rel="stylesheet" href="${path}${styles}"/>
  <div id="container">
    <aside>
        <figure>
            <img id="chartperson" src="${path}chartperson.svg" alt="" />
        </figure>
        <figcaption>
            <ul id="heading">
                <li id="title">
                  Site Quality Monitoring
                </li>
                <li id="subtitle">
                  Powered by koality
                </li>
            </ul>
            <ul id="description">
                <li>
                    <span>
                      Checks entire online stores and websites in minutes
                    </span>
                </li>
                <li>
                    <span>
                      Get notifications about common website issues as they occur
                    </span>
                </li>
                <li>
                    <span>
                      Easy setup: no site modification required
                    </span>
                </li>
            </ul>
            <button id="button-cta">
              <span></span>
              Start Monitoring
            </button>
        </figcaption>
    </aside>
  </div>
`;

const listOfApps = new Map([
    [
        "cpanel-sitejet-plugin",
        {
            bannerDisplayConditions: (mutation, bannerEl) => {
                const domainDetailsAdded = mutation.addedNodes[0]?.localName === "sitejet-domain-details";
                const listDomainsAdded = mutation.addedNodes[0]?.localName === "sitejet-list-domains";
                const templateChooserAdded = mutation.addedNodes[0]?.localName === "sitejet-template-chooser";

                if (domainDetailsAdded) bannerEl.style.display = "block";
                else if (listDomainsAdded || templateChooserAdded) bannerEl.style.display = "none";
            },
        }
    ],
    [
        "wordpress-toolkit",
        {
            bannerDisplayConditions: (mutation, bannerEl) => {
                const instancesListAdded = mutation.addedNodes[0]?.classList?.value.includes("wp-toolkit-instances-list");
                const emptyViewAdded = mutation.addedNodes[0]?.classList?.value.includes("pul-list-empty-view");
                const layoutRemoved = mutation.removedNodes[0]?.classList?.value.includes("wp-toolkit-layout");
                const emptyViewImage = document.querySelector(".pul-list-empty-view__image");

                // Different class names are being used on cl6
                const emptyViewAdded_cl6 = mutation.addedNodes[0]?.classList?.value.includes("pul-3-25-0-list-empty-view");
                const emptyViewImage_cl6 = document.querySelector(".pul-3-25-0-list-empty-view__image");

                // The list of sites is added on the "installations" tab if
                // there are wordpress sites but if there are none, then an
                // empty view is added and a starter image is added. We want to
                // display the banner in those situations.
                //
                // Note: If you switch tabs fast enough, sometimes your list of
                // instances doesn't show up and the empty view being added
                // isn't registered, so we also check if the emptyViewImage is
                // on the page as a backup check.
                if (instancesListAdded || (emptyViewAdded || emptyViewAdded_cl6) || (emptyViewImage || emptyViewImage_cl6)) bannerEl.style.display = "block";

                // The layout seems to be removed (and re-added) every time one
                // switches tabs (installations, plugins, themes) on the wptk
                // page. Afterwards it's typical for a loading screen to show
                // up. We don't want the banner displayed while things are
                // loading.
                else if (layoutRemoved) bannerEl.style.display = "none";
            },
        }
    ],
]);

class KoalityBanner extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: "open" });
        this.shadowRoot.appendChild(template.content.cloneNode(true));
        this.observeAppToDisplayBanner();
    }

    setupCtaButtonListener(appName) {
        const buttonEl = this.shadowRoot.getElementById("button-cta");
        const spanEl = buttonEl.querySelector("#button-cta span");

        buttonEl.addEventListener('click', () => {
            window["mixpanel"]?.track("cp-koality-banner-Clicked", { "app-key": appName });
            spanEl.className = "loading-animation";
            setTimeout(() => {
                spanEl.className = "";
            }, 10000);
            window.location.href = '../koality/signup/index.html';
        })
    }

    setupMutationObserverForApp(appOptions, bannerEl) {
        const targetEl = document.body;
        const mutationOptions = {
            childList: true,
            subtree: true,
        };
        const mutationCallback = (mutationList, mutationObserver) => {
            mutationList.forEach((mutation) => {
                appOptions.bannerDisplayConditions(mutation, bannerEl);
            });
        };
        const mutationObserver = new MutationObserver(mutationCallback);

        mutationObserver.observe(targetEl, mutationOptions);
    }

    setupIntersectionObserverForBanner(appName, bannerEl) {
        const instersectionOptions = {
            threshold: 0.75,
        };
        const intersectionCallback = (intersectionEntries, intersectionObserver) => {
            intersectionEntries.forEach((intersection) => {
                if (intersection.isIntersecting) {
                    window["mixpanel"]?.track("cp-koality-banner-Visible", { "app-key": appName });
                    intersectionObserver.unobserve(bannerEl);
                };
            });
        };
        const intersectionObserver = new IntersectionObserver(intersectionCallback, instersectionOptions);

        intersectionObserver.observe(bannerEl);
    }

    observeAppToDisplayBanner() {
        const bannerEl = this;

        listOfApps.forEach((appOptions, appKey) => {
            const currentApp = document.getElementById(appKey);
            if (currentApp) {
                this.setupCtaButtonListener(appKey);
                this.setupMutationObserverForApp(appOptions, bannerEl);
                this.setupIntersectionObserverForBanner(appKey, bannerEl);
                return;
            };
        });
    }
}

customElements.define("cp-koality-banner", KoalityBanner);
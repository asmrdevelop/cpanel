(function(){var DOM=YAHOO.util.Dom;var EVENT=YAHOO.util.Event;var CPVALIDATE=CPANEL.validate;var PAGE=window["PAGE"];var sendEmailValidator;var VALIDATORS=[];function isOptionalIfUndefined(el){if(el&&el.value!==""){return true}return false}function isAlphaOrWhitespace(el){if(el&&el.value!==""){return/^[\-A-Za-z ]+$/.test(el.value)}return false}function warnOnSpecialCharacters(evt,notice){if(this.value.match(/[^0-9a-zA-Z-,. ]/)){notice.show()}else{notice.hide()}}function registerValidators(){var i,l;var validation=new CPVALIDATE.validator(LOCALE.maketext("Contact Email Address"));validation.add("xemail","min_length(%input%, 1)",LOCALE.maketext("You must enter an email address."));validation.add("xemail","email(%input%)",LOCALE.maketext("The email address provided is not valid. This address must start with the mailbox name, then the “@” sign, then the mail domain name."));VALIDATORS.push(validation);sendEmailValidator=validation;validation=new CPVALIDATE.validator(LOCALE.maketext("Domain"));validation.add("domains",CPANEL.Applications.SSL.areValidSSLDomains,LOCALE.maketext("You can only enter valid domains."));VALIDATORS.push(validation);validation=new CPVALIDATE.validator(LOCALE.maketext("City"));validation.add("city","min_length(%input%, 1)",LOCALE.maketext("You must enter a city."),isOptionalIfUndefined);VALIDATORS.push(validation);validation=new CPVALIDATE.validator(LOCALE.maketext("State"));validation.add("state","min_length(%input%, 1)",LOCALE.maketext("You must enter a state."),isOptionalIfUndefined);VALIDATORS.push(validation);validation=new CPVALIDATE.validator(LOCALE.maketext("Country"));validation.add("country","min_length(%input%, 2)",LOCALE.maketext("Choose a country."),isOptionalIfUndefined);VALIDATORS.push(validation);validation=new CPVALIDATE.validator(LOCALE.maketext("Company"));validation.add("co","min_length(%input%, 1)",LOCALE.maketext("You must enter a company."),isOptionalIfUndefined);validation.add("co","max_length(%input%, 64)",LOCALE.maketext("The company name must be no longer than [quant,_1,character,characters].",64));VALIDATORS.push(validation);validation=new CPVALIDATE.validator(LOCALE.maketext("Company Division"));validation.add("cod","min_length(%input%, 1)",LOCALE.maketext("The “[_1]” field must be at least [quant,_2,character,characters] long.",LOCALE.maketext("Company Division"),2),isOptionalIfUndefined);validation.add("cod","max_length(%input%, 64)",LOCALE.maketext("The company division must be no longer than [quant,_1,character,characters].",64),isOptionalIfUndefined);VALIDATORS.push(validation);validation=new CPVALIDATE.validator(LOCALE.maketext("Certificate Email Address"));validation.add("email","min_length(%input%, 1)",LOCALE.maketext("You must enter an email address."),isOptionalIfUndefined);validation.add("email","email(%input%)",LOCALE.maketext("The email address provided is not valid. This address must start with the mailbox name, then the “@” sign, then the mail domain name."),isOptionalIfUndefined);VALIDATORS.push(validation);validation=new CPVALIDATE.validator(LOCALE.maketext("Passphrase"));validation.add("pass","min_length(%input%, 4)",LOCALE.maketext("The passphrase must be at least [quant,_1,character,characters] long.",4),isOptionalIfUndefined);validation.add("pass","max_length(%input%, 20)",LOCALE.maketext("The passphrase must be no longer than [quant,_1,character,characters].",20),isOptionalIfUndefined);validation.add("pass","alphanumeric",LOCALE.maketext("You entered an invalid character. The passphrase may contain only letters and numbers."),isOptionalIfUndefined);VALIDATORS.push(validation);for(i=0,l=VALIDATORS.length;i<l;i++){VALIDATORS[i].attach()}CPVALIDATE.attach_to_form("submit-button",VALIDATORS,{success_callback:handle_single_submission_lockout});var companyNotice=new CPANEL.widgets.Page_Notice({container:"co_warning",level:"warn",content:LOCALE.maketext("This field contains characters that some certificate authorities may not accept. Contact your certificate authority to confirm that they accept these characters."),visible:false});var divisionNotice=new CPANEL.widgets.Page_Notice({container:"cod_warning",level:"warn",content:LOCALE.maketext("This field contains characters that some certificate authorities may not accept. Contact your certificate authority to confirm that they accept these characters."),visible:false});var events_to_listen=CPANEL.dom.has_oninput?["input"]:["paste","keyup","change"];events_to_listen.forEach((function(evt){EVENT.on("co",evt,warnOnSpecialCharacters,companyNotice);EVENT.on("cod",evt,warnOnSpecialCharacters,divisionNotice)}))}function toggleSendToEmail(e){var xemailEl=DOM.get("xemail");if(this.checked){xemailEl.disabled=false;xemailEl.focus();if(sendEmailValidator){sendEmailValidator.verify()}}else{xemailEl.disabled=true;if(sendEmailValidator){sendEmailValidator.clear_messages()}}}var moveCaretToEnd=function(el){if(el.createTextRange){var fieldRange=el.createTextRange();fieldRange.moveStart("character",el.value.length);fieldRange.collapse();fieldRange.select()}else{el.focus();var length=el.value.length;el.setSelectionRange(length,length)}};var delayedMoveCaretToEnd=function(el,delay){if(typeof delay==="undefined"){delay=0}setTimeout((function(){moveCaretToEnd(el)}),delay)};function initialize(){EVENT.on("sendemail","click",toggleSendToEmail);registerValidators();var sendemail=DOM.get("sendemail");sendemail.focus();if(sendemail.checked){var xemailEl=DOM.get("xemail");xemailEl.disabled=false;if(sendEmailValidator){sendEmailValidator.verify()}}}EVENT.addListener(window,"load",initialize)})();
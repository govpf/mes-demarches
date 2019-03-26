# API URLs
API_ADRESSE_URL = ENV.fetch("API_ADRESSE_URL", "https://api-adresse.data.gouv.fr")
API_CARTO_URL = ENV.fetch("API_CARTO_URL", "https://apicarto.sgmap.fr")
API_ENTREPRISE_URL = ENV.fetch("API_ENTREPRISE_URL", "https://entreprise.api.gouv.fr/v2")
API_GEO_URL = ENV.fetch("API_GEO_URL", "https://geo.api.gouv.fr")
API_GEO_SANDBOX_URL = ENV.fetch("API_GEO_SANDBOX_URL", "https://sandbox.geo.api.gouv.fr")
HELPSCOUT_API_URL = ENV.fetch("HELPSCOUT_API_URL", "https://api.helpscout.net/v2")
PIPEDRIVE_API_URL = ENV.fetch("PIPEDRIVE_API_URL", "https://api.pipedrive.com/v1")

API_ENTREPRISE_PF_URL = ENV.fetch("API_ENTREPRISE_PF_URL", "https://ppr.api.i-taiete2.gov.pf/api/v2")

# Internal URLs
FOG_BASE_URL = "https://static.demarches-simplifiees.fr"

# External services URLs
FR_DOC_URL = "https://doc.demarches-simplifiees.fr"
DOC_URL = "https://doc.projet.gov.pf/display/DEM"
ADMINISTRATEUR_TUTORIAL_URL = [DOC_URL, "Dématérialiser+un+premier+formulaire"].join("/")
INSTRUCTEUR_TUTORIAL_URL = [DOC_URL, "Tutoriels"].join("/")
CADRE_JURIDIQUE_URL = [ADMINISTRATEUR_TUTORIAL_URL, "cadre-juridique"].join("#") # TODO version polynésie
LISTE_DES_DEMARCHES_URL = [DOC_URL, "Liste+des+démarches"].join("/")
CGU_URL = [DOC_URL, "CGU"].join("/")
MENTIONS_LEGALES_URL = [CGU_URL, "mentions-legales"].join("#")
API_DOC_URL = [FR_DOC_URL, "pour-aller-plus-loin", "api"].join("/")
WEBHOOK_DOC_URL = [FR_DOC_URL, "pour-aller-plus-loin", "webhook"].join("/")
FAQ_URL = [DOC_URL, "pages/viewpage.action?pageId=19764339"].join("/")
STATUS_PAGE_URL = "https://status.demarches-simplifiees.fr"
MATOMO_IFRAME_URL = "https://stats.data.gouv.fr/index.php?module=CoreAdminHome&action=optOut&language=fr&&fontColor=333333&fontSize=16px&fontFamily=Muli"

import html
import time

import requests
import streamlit as st

# ============================================================
# CONFIGURATION
# ============================================================

DEFAULT_API_URL = "https://76a7-136-66-199-225.ngrok-free.app/ask"

SUGGESTIONS = [
    "Qu'est-ce qu'une fissure longitudinale et quelles sont ses caractéristiques ?",
    "Quelle est la différence entre le faïençage et la fissuration transversale ?",
    "Quelles sont les causes principales d'un nid-de-poule ?",
    "Comment évaluer la gravité d'une ornière sur une chaussée ?",
]

LOGO = """
<svg width="38" height="38" viewBox="0 0 36 36" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
  <rect width="36" height="36" rx="9" fill="#12355B"/>
  <path d="M12 29 L16.4 8 H19.6 L24 29 Z" fill="#2C5282"/>
  <path d="M18 10.5 V13.5 M18 16.5 V20 M18 23 V27.5" stroke="#F2A900" stroke-width="1.9" stroke-linecap="round"/>
</svg>
"""

st.set_page_config(
    page_title="Road Damage Assistant",
    page_icon="🛣️",
    layout="wide",
    initial_sidebar_state="expanded",
)

# ============================================================
# STYLE
# ============================================================

st.markdown(
    """
<style>
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap');

:root {
    --bg: #F4F6F9;
    --surface: #FFFFFF;
    --border: #E1E6ED;
    --text: #0F1A2A;
    --muted: #5B6778;
    --primary: #12355B;
    --primary-hover: #0D2945;
    --primary-soft: #E8EEF6;
    --amber: #F2A900;
    --radius: 10px;
    --shadow: 0 1px 2px rgba(16, 32, 56, .06), 0 4px 14px rgba(16, 32, 56, .04);
}

html, body, [class*="css"], .stApp, button, input, textarea {
    font-family: 'Inter', -apple-system, 'Segoe UI', sans-serif !important;
    color: var(--text);
}
.stApp { background: var(--bg); }

#MainMenu, footer, header[data-testid="stHeader"] { visibility: hidden; height: 0; }
.block-container { max-width: 880px; padding-top: 1.4rem; padding-bottom: 7rem; }

/* ---------- Barre supérieure ---------- */
.topbar {
    display: flex; align-items: center; gap: .85rem;
    padding-bottom: 1.1rem; margin-bottom: 1.6rem;
    border-bottom: 1px solid var(--border);
}
.topbar-title { font-size: 1.15rem; font-weight: 700; letter-spacing: -.01em; line-height: 1.2; }
.topbar-sub { font-size: .85rem; color: var(--muted); }
.status {
    margin-left: auto; display: inline-flex; align-items: center; gap: .45rem;
    font-size: .8rem; font-weight: 500; color: var(--muted);
    background: var(--surface); border: 1px solid var(--border);
    border-radius: 999px; padding: .3rem .75rem;
}
.status i { width: 7px; height: 7px; border-radius: 50%; background: #2F9E6B; display: inline-block; }

/* ---------- État vide ---------- */
.empty h1 {
    font-size: clamp(1.7rem, 3.6vw, 2.25rem); font-weight: 700;
    letter-spacing: -.025em; line-height: 1.15; margin: 1.2rem 0 .6rem; max-width: 20ch;
}
.empty p { color: var(--muted); font-size: 1.02rem; line-height: 1.55; max-width: 56ch; margin: 0 0 1.6rem; }

[class*="st-key-sg_"] button {
    background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius);
    box-shadow: var(--shadow); text-align: left; justify-content: flex-start;
    padding: .95rem 1.05rem; min-height: 4.6rem; width: 100%;
    color: var(--text); font-size: .93rem; line-height: 1.45; font-weight: 500;
    transition: border-color .15s, box-shadow .15s;
}
[class*="st-key-sg_"] button:hover { border-color: var(--primary); color: var(--primary); }
[class*="st-key-sg_"] button p { text-align: left; }

/* ---------- Conversation ---------- */
.user-row { display: flex; justify-content: flex-end; margin: 1.6rem 0 .9rem; }
.user-bubble {
    background: var(--primary); color: #fff; padding: .75rem 1.05rem;
    border-radius: 14px 14px 4px 14px; max-width: 78%;
    font-size: .98rem; line-height: 1.5;
}

[data-testid="stChatMessage"] {
    background: var(--surface); border: 1px solid var(--border);
    border-radius: var(--radius); box-shadow: var(--shadow);
    padding: 1.2rem 1.4rem 1.3rem;
}
[data-testid^="stChatMessageAvatar"] { display: none; }
[data-testid="stChatMessage"] p, [data-testid="stChatMessage"] li { font-size: 1rem; line-height: 1.7; }
[data-testid="stChatMessage"] strong { font-weight: 600; }

/* Indicateurs */
.chips { display: flex; flex-wrap: wrap; gap: .5rem; margin: 1rem 0 0; }
.chip {
    font-size: .8rem; font-weight: 500; color: var(--muted);
    background: var(--bg); border: 1px solid var(--border);
    border-radius: 6px; padding: .22rem .6rem;
}

/* ---------- Sources ---------- */
.src-heading {
    font-size: .92rem; font-weight: 600; margin: 1.5rem 0 .7rem;
    padding-top: 1.1rem; border-top: 1px solid var(--border);
}
.src-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: .75rem; align-items: start; }
@media (max-width: 720px) { .src-grid { grid-template-columns: 1fr; } }

details.src {
    background: var(--bg); border: 1px solid var(--border);
    border-radius: 8px; padding: .8rem .95rem;
}
details.src[open] { background: var(--surface); border-color: #BFCBDB; grid-column: 1 / -1; }
details.src summary { list-style: none; cursor: pointer; }
details.src summary::-webkit-details-marker { display: none; }
details.src summary:focus-visible { outline: 2px solid var(--primary); outline-offset: 4px; border-radius: 4px; }

.src-head { display: flex; align-items: center; gap: .6rem; margin-bottom: .5rem; }
.src-idx {
    flex: none; width: 22px; height: 22px; border-radius: 6px;
    background: var(--primary-soft); color: var(--primary);
    font-size: .75rem; font-weight: 600; display: grid; place-items: center;
}
.src-name {
    font-size: .86rem; font-weight: 600; flex: 1; min-width: 0;
    overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
.src-score { font-size: .78rem; font-weight: 600; color: var(--primary); font-variant-numeric: tabular-nums; }
.src-bar { height: 4px; background: var(--border); border-radius: 2px; overflow: hidden; margin-bottom: .6rem; }
.src-bar span { display: block; height: 100%; background: var(--primary); border-radius: 2px; }

.src-preview {
    font-size: .86rem; line-height: 1.5; color: var(--muted);
    display: -webkit-box; -webkit-line-clamp: 3; -webkit-box-orient: vertical; overflow: hidden;
}
details.src[open] .src-preview { display: none; }
.src-full { font-size: .9rem; line-height: 1.65; color: var(--text); white-space: pre-wrap; margin-top: .2rem; }

/* ---------- Zone de saisie ---------- */
[data-testid="stBottom"] > div { background: linear-gradient(to top, var(--bg) 70%, transparent); }
[data-testid="stChatInput"] {
    background: var(--surface); border: 1px solid var(--border);
    border-radius: 12px; box-shadow: var(--shadow);
}
[data-testid="stChatInput"]:focus-within { border-color: var(--primary); box-shadow: 0 0 0 3px rgba(18, 53, 91, .15); }
[data-testid="stChatInput"] textarea { font-size: .98rem; }
[data-testid="stChatInput"] button { background: var(--primary); color: #fff; border-radius: 8px; }
[data-testid="stChatInput"] button:hover { background: var(--primary-hover); }

.disclaimer { text-align: center; color: var(--muted); font-size: .78rem; margin-top: 2.2rem; }

/* ---------- Barre latérale ---------- */
[data-testid="stSidebar"] { background: var(--surface); border-right: 1px solid var(--border); }
[data-testid="stSidebar"] .block-container { padding-top: 1.4rem; }
.side-title { font-size: .95rem; font-weight: 600; margin-bottom: .2rem; }
.side-note { font-size: .82rem; color: var(--muted); line-height: 1.5; }
[data-testid="stSidebar"] button {
    border: 1px solid var(--border); border-radius: 8px; background: var(--surface);
    font-weight: 500; font-size: .88rem;
}
[data-testid="stSidebar"] button:hover { border-color: var(--primary); color: var(--primary); }

@media (prefers-reduced-motion: reduce) { * { transition: none !important; } }
</style>
""",
    unsafe_allow_html=True,
)

# ============================================================
# ÉTAT
# ============================================================

if "history" not in st.session_state:
    st.session_state.history = []


def use_suggestion(text: str):
    st.session_state.pending = text


# ============================================================
# APPEL API COLAB
# ============================================================


def ask_rag_api(api_url, question, k=5):
    response = requests.post(
        api_url,
        json={"question": question, "k": k},
        headers={"ngrok-skip-browser-warning": "true"},
        timeout=300,
    )
    response.raise_for_status()
    return response.json()


# ============================================================
# COMPOSANTS D'AFFICHAGE
# ============================================================


def render_question(text: str):
    st.markdown(
        f'<div class="user-row"><div class="user-bubble">{html.escape(text)}</div></div>',
        unsafe_allow_html=True,
    )


def sources_html(sources):
    cards = []
    for i, s in enumerate(sources, 1):
        score = float(s["score"])
        width = max(0.0, min(score, 1.0)) * 100
        text = html.escape(s["text"])
        cards.append(
            f"""
<details class="src">
  <summary>
    <div class="src-head">
      <span class="src-idx">{i}</span>
      <span class="src-name" title="{html.escape(str(s['source']))}">{html.escape(str(s['source']))}</span>
      <span class="src-score">{score:.3f}</span>
    </div>
    <div class="src-bar"><span style="width:{width:.0f}%"></span></div>
    <div class="src-preview">{text}</div>
  </summary>
  <div class="src-full">{text}</div>
</details>"""
        )
    return (
        f'<div class="src-heading">Sources ({len(sources)})</div>'
        f'<div class="src-grid">{"".join(cards)}</div>'
    )


def render_answer(item):
    best = max((float(s["score"]) for s in item["sources"]), default=0.0)
    with st.chat_message("assistant"):
        st.markdown(item["answer"])
        st.markdown(
            f"""
<div class="chips">
  <span class="chip">{item["duration"]:.1f} s</span>
  <span class="chip">{len(item["sources"])} passages</span>
  <span class="chip">Pertinence max. {best:.3f}</span>
</div>
{sources_html(item["sources"])}
""",
            unsafe_allow_html=True,
        )


# ============================================================
# BARRE LATÉRALE
# ============================================================

with st.sidebar:
    st.markdown('<div class="side-title">Paramètres de recherche</div>', unsafe_allow_html=True)
    st.markdown(
        '<div class="side-note">Ajustez la quantité de contexte envoyée au modèle.</div>',
        unsafe_allow_html=True,
    )
    k = st.slider("Passages récupérés", 1, 10, 5)
    api_url = st.text_input(
        "URL de l'API",
        value=DEFAULT_API_URL,
        help="L'adresse ngrok change à chaque redémarrage de Colab.",
    )
    st.markdown("&nbsp;", unsafe_allow_html=True)
    if st.button("Nouvelle conversation", use_container_width=True):
        st.session_state.history = []
        st.rerun()

# ============================================================
# EN-TÊTE
# ============================================================

st.markdown(
    f"""
<div class="topbar">
  {LOGO}
  <div>
    <div class="topbar-title">Road Damage Assistant</div>
    <div class="topbar-sub">Pathologies et dégradations des chaussées</div>
  </div>
  <div class="status"><i></i>Base documentaire active</div>
</div>
""",
    unsafe_allow_html=True,
)

# ============================================================
# SAISIE
# ============================================================

typed = st.chat_input("Posez votre question sur les dommages routiers…")
prompt = typed or st.session_state.pop("pending", None)

# ============================================================
# ÉTAT VIDE
# ============================================================

if not st.session_state.history and not prompt:
    st.markdown(
        """
<div class="empty">
  <h1>Que voulez-vous savoir sur les dégradations routières ?</h1>
  <p>Chaque réponse est rédigée à partir de vos documents techniques.
  Les passages utilisés sont listés en dessous pour pouvoir les vérifier.</p>
</div>
""",
        unsafe_allow_html=True,
    )
    cols = st.columns(2)
    for i, text in enumerate(SUGGESTIONS):
        cols[i % 2].button(text, key=f"sg_{i}", on_click=use_suggestion, args=(text,))

# ============================================================
# CONVERSATION
# ============================================================

for item in st.session_state.history:
    render_question(item["question"])
    render_answer(item)

if prompt:
    render_question(prompt)
    start = time.time()
    try:
        with st.spinner("Recherche dans les documents et rédaction de la réponse…"):
            result = ask_rag_api(api_url, prompt.strip(), k=k)
        item = {
            "question": prompt.strip(),
            "answer": result["answer"],
            "sources": result["sources"],
            "duration": time.time() - start,
        }
        st.session_state.history.append(item)
        render_answer(item)
    except requests.exceptions.Timeout:
        st.error(
            "Le serveur Colab n'a pas répondu en 5 minutes. "
            "Vérifiez que le notebook tourne encore, puis réessayez."
        )
    except requests.exceptions.RequestException as e:
        st.error(
            "Impossible de joindre l'API. Vérifiez l'URL dans les paramètres "
            f"(elle change à chaque session Colab).\n\nDétail : {e}"
        )
    except (KeyError, ValueError) as e:
        st.error(f"La réponse de l'API n'a pas le format attendu : {e}")

if st.session_state.history:
    st.markdown(
        '<div class="disclaimer">Les réponses sont générées par un modèle : '
        "vérifiez les sources pour toute décision technique.</div>",
        unsafe_allow_html=True,
    )
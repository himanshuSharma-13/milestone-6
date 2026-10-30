"""Three-view QA dashboard for Streamlit in Snowflake. All data are synthetic."""
import plotly.graph_objects as go
import streamlit as st
from snowflake.snowpark.context import get_active_session

st.set_page_config(page_title="PIP assessment quality", layout="wide")
session = get_active_session()

@st.cache_data(ttl=300)
def query(sql):
    return session.sql(sql).to_pandas()

st.title("PIP assessment quality")
st.caption("Synthetic demonstration data. Use for QA review, not automated claimant or assessor decisions.")
view = st.sidebar.radio("View", ["KPI overview", "At-risk caseload", "Assessor consistency"])

if view == "KPI overview":
    awards = query("SELECT COMPONENT, AWARD_LEVEL, REGION, SUM(CASES) CASES FROM PIP_QUALITY.MART.AWARD_RATES GROUP BY 1,2,3")
    overturn = query("SELECT * FROM PIP_QUALITY.MART.OVERTURN_RATES")
    quality = query("SELECT AVG(AVG_AUDIT_QUALITY_SCORE) SCORE FROM PIP_QUALITY.MART.ASSESSOR_QUALITY")
    c1, c2, c3 = st.columns(3)
    c1.metric("Closed component decisions", int(awards.CASES.sum()))
    c2.metric("MR overturn rate", f"{float(overturn.iloc[0].OVERTURN_RATE):.1%}")
    c3.metric("Mean assessor audit score", f"{float(quality.iloc[0].SCORE):.2f}/5")
    st.subheader("Award outcomes by component and region")
    st.bar_chart(awards, x="REGION", y="CASES", color="AWARD_LEVEL", stack=True)
    st.dataframe(query("SELECT COMPONENT, AWARD_LEVEL, REGION, ASSESSOR_ID, ASSESSMENT_TYPE, CASES, AWARD_RATE, AVG_POINTS, MEDIAN_TURNAROUND_DAYS, P90_TURNAROUND_DAYS FROM PIP_QUALITY.MART.AWARD_RATES ORDER BY COMPONENT,REGION"), use_container_width=True)

elif view == "At-risk caseload":
    st.write("Open cases at day 35 or later against an assumed 40-day target.")
    risk = query("SELECT CASE_ID, ASSESSOR_ID, TEAM_ID, REGION, ASSESSMENT_TYPE, REFERRAL_DATE, DAYS_OPEN, DAYS_TO_TARGET FROM PIP_QUALITY.MART.AT_RISK_CASES ORDER BY DAYS_TO_TARGET,CASE_ID")
    st.metric("Cases needing review", len(risk))
    st.dataframe(risk, use_container_width=True)

else:
    st.write("Funnel limits account for caseload size and standardize for assessment type and condition category.")
    funnel = query("SELECT * FROM PIP_QUALITY.MART.FUNNEL ORDER BY N")
    fig = go.Figure()
    for name, col, color in [("Observed", "OBSERVED_RATE", "#175cd3"),
                             ("Expected", "EXPECTED_RATE", "#344054"),
                             ("95% lower", "LOWER_95", "#98a2b3"),
                             ("95% upper", "UPPER_95", "#98a2b3"),
                             ("99.8% lower", "LOWER_998", "#d92d20"),
                             ("99.8% upper", "UPPER_998", "#d92d20")]:
        fig.add_trace(go.Scatter(x=funnel.N, y=funnel[col], mode="markers" if name == "Observed" else "lines",
                                 name=name, text=funnel.ASSESSOR_ID, line=dict(color=color)))
    fig.update_layout(xaxis_title="Completed cases per assessor", yaxis_title="Daily living award rate",
                      yaxis_tickformat=".0%", height=480)
    st.plotly_chart(fig, use_container_width=True)
    st.dataframe(funnel, use_container_width=True)
    st.subheader("Current month's immutable audit sample")
    sample = query("SELECT SAMPLE_MONTH,CASE_ID,REGION,ASSESSMENT_TYPE,OUTCOME,RISK_FLAG,RATIONALE,RUN_DATE FROM PIP_QUALITY.MART.AUDIT_SAMPLE WHERE SAMPLE_MONTH=DATE_TRUNC('MONTH',CURRENT_DATE())::DATE ORDER BY REGION,ASSESSMENT_TYPE,CASE_ID")
    st.dataframe(sample, use_container_width=True)
    st.subheader("Points versus recorded band exceptions")
    st.dataframe(query("SELECT * FROM PIP_QUALITY.MART.CONSISTENCY_EXCEPTIONS ORDER BY EXCEPTION_RATE DESC"), use_container_width=True)

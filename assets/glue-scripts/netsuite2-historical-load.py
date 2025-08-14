# assets/glue-scripts/netsuite2-historical-load-suiteql.py
import sys
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
import boto3
import json
import requests
from requests_oauthlib import OAuth1
import pandas as pd
from datetime import datetime

# Parse arguments
args = getResolvedOptions(sys.argv, ["JOB_NAME", "start_date", "end_date", "secret_name"])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args["JOB_NAME"], args)

start_date = args['start_date']
end_date = args['end_date']
secret_name = args['secret_name']

print(f"INFO: Running job for period: {start_date} to {end_date}")
print(f"INFO: Retrieving secret '{secret_name}'...")

# Retrieve NetSuite API credentials from Secrets Manager
try:
    session = boto3.session.Session()
    client = session.client(service_name="secretsmanager")
    get_secret_value_response = client.get_secret_value(SecretId=secret_name)
    secret = get_secret_value_response["SecretString"]
    secret_dict = json.loads(secret)
    BASE_URL = secret_dict["BASE_URL"]
    ACCOUNT_ID = secret_dict["ACCOUNT_ID"]
    CONSUMER_KEY = secret_dict["CONSUMER_KEY"]
    CONSUMER_SECRET = secret_dict["CONSUMER_SECRET"]
    TOKEN_ID = secret_dict["TOKEN_ID"]
    TOKEN_SECRET = secret_dict["TOKEN_SECRET"]
    print("INFO: Successfully retrieved credentials.")
except Exception as e:
    print(f"ERROR: Failed to retrieve or parse secret: {e}")
    raise e

# Construct the SuiteQL query payload
SUITEQL_QUERY = {
    "q": f"""
        SELECT 
            accountinglinetype, acknowledgefulfillinstruction, actualshipdate, allocationalert, altsalesamt, 
            amortizationenddate, amortizationresidual, amortizationsched, amortizstartdate, assembly, 
            assemblycomponent, assemblyunits, basegrossamt, basetaxamount, billeddate, billingschedule, 
            billofmaterials, billofmaterialsrevision, billvariancestatus, blandedcost, bomquantity, buildvariance, 
            catchupperiod, category, chargetype, class, cleared, cleareddate, closedate, commitinventory, commitmentfirm, 
            componentyield, costestimate, costestimatebase, costestimaterate, costestimatetype, createdfrom, createdpo, createexpenseplanson, 
            createoutsourcedwo, creditforeignamount, custcol1, custcol_concur_emp_first_name, custcol_concur_emp_last_name, 
            custcol_concur_employee_id, custcol_concur_invoice_number, custcol_concur_report_id, custcol_concur_report_type, 
            custcol_cseg_p_l_v, custcol_idt_buyer_provincial_reg, custcol_idt_buyer_registration, custcol_idt_commodity_code, 
            custcol_idt_credit_tax_amt, custcol_idt_jurisdiction_txt_summary, custcol_idt_pretax_amt, custcol_idt_pretax_amt_qty, 
            custcol_idt_product_tax_code, custcol_idt_seller_provincial_reg, custcol_idt_seller_registration, custcol_idt_tax_amt, 
            custcol_idt_tax_exemption, custcol_idt_tax_exemption_reason, custcol_idt_tax_rate, custcol_idt_vendor_tax, custcol_inv_road_hazard_cf, 
            custcol_ls_065_netting_account, custcol_ls_084_line_acc, custcol_ls_084_line_dept, custcol_ls_1099_misc_items, custcol_ls_1099misc_box, 
            custcol_ls_20_item_billed, custcol_ls_20_old_quantity, custcol_ls_accrued_fet, custcol_ls_accrued_freight, custcol_ls_adj_code, 
            custcol_ls_adj_percent, custcol_ls_adjustment_current_month, custcol_ls_ap_code, custcol_ls_ap_cost, custcol_ls_backorder_flag, 
            custcol_ls_balance_subject_to_interes, custcol_ls_base_price, custcol_ls_bill_posting_period_inv, custcol_ls_cash_discount, 
            custcol_ls_cf_sku, custcol_ls_column_uti, custcol_ls_concur_employee, custcol_ls_container_number, custcol_ls_conterpartyco, 
            custcol_ls_contract_ext_price, custcol_ls_contract_unit_price, custcol_ls_contrct_mngr, custcol_ls_core_amount, 
            custcol_ls_counterparty_location, custcol_ls_counterparty_location_text, custcol_ls_dep_line_seqno, custcol_ls_dependent_line, 
            custcol_ls_deposit_reclass_executed, custcol_ls_deposit_source, custcol_ls_description_1, custcol_ls_description_2, 
            custcol_ls_description_3, custcol_ls_discount, custcol_ls_division_department, custcol_ls_due_to_wh, custcol_ls_eliminate_reporting, 
            custcol_ls_exclude_cash_discount, custcol_ls_ext_fet, custcol_ls_extunit_price_excl_fet, custcol_ls_home_office_location, 
            custcol_ls_interest_rate, custcol_ls_invoice_freight, custcol_ls_is_qtydisc, custcol_ls_iseries_deposit_type, 
            custcol_ls_iseries_deposit_type_text, custcol_ls_item_income_accnt, custcol_ls_item_receipt, custcol_ls_item_receipt_link, 
            custcol_ls_je_link, custcol_ls_kyr_trans_amount, custcol_ls_liab_ins, custcol_ls_line_number, custcol_ls_location, custcol_ls_lsp_code, 
            custcol_ls_lsp_coded_item, custcol_ls_lsp_item_ref, custcol_ls_manual_po_no, custcol_ls_markup_percentage, custcol_ls_mfcs_item_ref, 
            custcol_ls_mfcs_item_ref_po, custcol_ls_mfcs_transfer_no, custcol_ls_non_disc, custcol_ls_non_disc3, custcol_ls_non_disc4, 
            custcol_ls_off_invoice_disc, custcol_ls_over_short_qty, custcol_ls_pack_slip_no, custcol_ls_packing_slip, custcol_ls_parameters, 
            custcol_ls_po_previous_rate, custcol_ls_posting_account, custcol_ls_posting_code, custcol_ls_posting_div_dep, custcol_ls_price_diff_amt, 
            custcol_ls_price_diff_flag, custcol_ls_price_disc, custcol_ls_price_discrepancy, custcol_ls_price_eff_date, custcol_ls_project, 
            custcol_ls_purchase_order, custcol_ls_purchase_order_link, custcol_ls_purchases_current_month, custcol_ls_putaway_no, 
            custcol_ls_qty_received, custcol_ls_qty_remaining, custcol_ls_quantity_discrepancy, custcol_ls_quantitybilled, 
            custcol_ls_rebill_account, custcol_ls_rebill_dept, custcol_ls_rebill_error_code, custcol_ls_rebill_line_no, custcol_ls_rebill_memo, 
            custcol_ls_rebill_status, custcol_ls_receiving_date, custcol_ls_rep_sub, custcol_ls_rtv_no, custcol_ls_sales_order_no, 
            custcol_ls_store_account, custcol_ls_store_cost, custcol_ls_store_unit_cost, custcol_ls_subsidiary, custcol_ls_tc_prod_line, 
            custcol_ls_to_amortize, custcol_ls_unit_fet, custcol_ls_unitprice_excl_fet, custcol_ls_upc, custcol_ls_vb_line_no, 
            custcol_ls_vbd1, custcol_ls_vbd2, custcol_ls_vbd3, custcol_ls_vbd4, custcol_ls_vendor_price, custcol_ls_vendor_quantity, 
            custcol_ls_warehouse_cost, custcol_ls_warranty_allowance, custcol_ls_whz_account, custcol_ls_whz_amount, 
            custcol_ls_whz_division_department, custcol_ls_work_order_no, custcol_scm_item_ref, custcol_scm_je_account, 
            custcol_test_account, custcol_test_location, custcol_test_subsidiary, dayslate, debitforeignamount, deferrevrec, department, 
            documentnumber, donotcreaterevenueelement, donotdisplayline, donotprintline, dropship, duedate, duetofromsubsidiary, eliminate, 
            entity, estgrossprofit, estgrossprofitpercent, estimatedamount, excludefrompredictiverisk, excludefromraterequest, expecteddeliverydate,
            expectedreceiptdate, expectedshipdate, expenseaccount, expenseamortizationrule, expenseplanstatus, foreignamount, foreignamountpaid, 
            foreignamountpaidnopost, foreignamountunpaid, foreignpaymentamountunused, foreignpaymentamountused, foreignpaymentamountusednopost, 
            fulfillable, fulfillmentinstruction, fxamountlinked, fxvsoeallocation, fxvsoeamount, fxvsoeprice, grossamt, hascostline, 
            hasfulfillableitems, id, inventorylocation, inventoryreportinglocation, inventorysubsidiary, invsoebundle, isallocatefirminvtonly, 
            isallocation, isbillable, isbomrevisioncomponent, isclosed, iscogs, iscustomglline, isdisplayedinpaycheck, isfreezefirmallocation, 
            isfullyshipped, isfxvariance, isinventoryaffecting, isnonreimbursable, isrevrectransaction, isscrap, isvsoealloc, item, 
            itemfulfillmentchoice, itemsource, itemtype, kitcomponent, kitmemberof, landedcostcategory, landedcostperline, linelastmodifieddate, 
            linesequencenumber, linkedassemblybuild, linkedinventorytransfer, location, mainline, matchbilltoreceipt, memo, needsrevenueelement,
            netaltsalesamt, netamount, oldcommitmentfirm, operationdisplaytext, orderallocationstrategy, orderpriority, payitem, paymentmethod,
            periodclosed, porate, price, processedbyrevcommit, productionenddate, productionstartdate, projecttask, promisedate, quantity, 
            quantityallocated, quantitybackordered, quantitybilled, quantitycommitted, quantitydemandallocated, quantityonshipments, 
            quantitypacked, quantitypicked, quantityrejected, quantityrequestedtofulfill, quantityrevcommitted, quantityshiprecv, rate, 
            rateamount, ratepercent, requesteddate, requesteddeliverydate, requestnote, requireddepositamount, revcommittingtransaction, 
            revenueelement, revrecenddate, revrecschedule, revrecstartdate, revrecterminmonths, secondaryquantity, secondaryunits, 
            settlementamount, shipmethod, sourcesubsidiary, specialorder, subscription, subscriptionline, subsidiary, targetlocation, 
            targetsubsidiary, taxamount, taxline, transaction, transactiondiscount, transactionlinetype, transferorderitemlineid, 
            undeferredaccountinglinetype, uniquekey, units, vsoeallocation, vsoeamount, vsoedeferral, vsoedelivered, vsoeisestimate, 
            vsoepermitdiscount, vsoeprice, vsoesopgroup
        FROM 
            transactionline
        WHERE
            linelastmodifieddate >= '{start_date} 00:00:00'
            AND linelastmodifieddate < '{end_date} 00:00:00'
    """
}

# OAuth1 authentication
oauth = OAuth1(CONSUMER_KEY,
               client_secret=CONSUMER_SECRET,
               resource_owner_key=TOKEN_ID,
               resource_owner_secret=TOKEN_SECRET,
               realm=ACCOUNT_ID)

headers = {
    "Content-Type": "application/json",
    "Accept": "application/json"
}

# REST query endpoint
endpoint = f"{BASE_URL}"

print("INFO: Initializing SuiteQL REST query...")

all_records = []
try:
    response = requests.post(endpoint, json=SUITEQL_QUERY, headers=headers, auth=oauth)
    response.raise_for_status()
    result = response.json()
    
    if result.get('items'):
        all_records.extend(result['items'])
    
    # Handle pagination
    while 'links' in result:
        next_link = next((item['href'] for item in result['links'] if item['rel'] == 'next'), None)
        if next_link:
            response = requests.get(next_link, headers=headers, auth=oauth)
            response.raise_for_status()
            result = response.json()
            if result.get('items'):
                all_records.extend(result['items'])
        else:
            break

    record_count = len(all_records)

except requests.exceptions.HTTPError as errh:
    print(f"ERROR: Http Error: {errh}")
    raise errh
except requests.exceptions.ConnectionError as errc:
    print(f"ERROR: Error Connecting: {errc}")
    raise errc
except requests.exceptions.Timeout as errt:
    print(f"ERROR: Timeout Error: {errt}")
    raise errt
except requests.exceptions.RequestException as err:
    print(f"ERROR: OOps: Something Else {err}")
    raise err

if record_count == 0:
    print(f"WARN: Query returned 0 records for the period {start_date} to {end_date}. This may be expected.")
else:
    print(f"INFO: Read completed. {record_count} records found.")
    
    # Convert to Pandas DataFrame and then to Glue DynamicFrame
    df = pd.DataFrame(all_records)
    source_dyf = glueContext.create_dynamic_frame.from_pandas(df, name="netsuite_dynamic_frame")

    s3_output_path = f"s3://ls-snowflake-qa-etl/SNOWPIPE/NETSUITE/HISTORICALLOAD/TRANSACTIONLINE/load_date={start_date}/"
    print(f"INFO: Writing data to: {s3_output_path}...")

    glueContext.write_dynamic_frame.from_options(
        frame=source_dyf,
        connection_type="s3",
        connection_options={"path": s3_output_path},
        format="parquet",
        transformation_ctx="sink_s3",
    )
    print("INFO: S3 write successful.")

job.commit()
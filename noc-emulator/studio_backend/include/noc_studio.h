#ifndef NOC_STUDIO_H
#define NOC_STUDIO_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Small JSON request/response; packet arrays stay in native memory.
 * run is synchronous. On error the response contains {"error": ...}.
 * Caller releases every non-null response with noc_studio_v1_free.
 * Device paths: NOC_XDMA_H2C / NOC_XDMA_C2H (optional environment variables).
 */
int32_t noc_studio_v1_run(const char *request_json, char **response_json);
void noc_studio_v1_free(char *response_json);
/* Static borrowed JSON string; does not open or run the FPGA. */
const char *noc_studio_v1_capabilities(void);
#ifdef __cplusplus
}
#endif
#endif
